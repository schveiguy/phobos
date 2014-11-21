/**
Text io buffer definition

Source: $(PHOBOSSRC std/io/_text.d)

Copyright: Copyright Digital Mars 2014-.
License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors:   Steven Schveighoffer
 */
module std.io.text;
import std.io.stream;
import std.io.traits;
import std.io.buffer;
private import std.algorithm;
private import std.range;
private import core.bitop;
private import std.traits;
private import std.conv;
private import std.utf;
private import std.format;

debug import std.stdio;

// This uses inline utf decoding/encoding instead of calling runtime functions.
version = inlineutf;

/**
 * The width of a text stream
 */
enum StreamWidth : ubyte
{
    /// Determine width from stream itself
    AUTO = 0,

    /// 8 bit width
    UTF8 = 1,

    /// 16 bit width
    UTF16 = 2,

    /// 32 bit width
    UTF32 = 4
}

/**
 * The byte order of a buffer stream
 */
enum ByteOrder : ubyte
{
    /// Byte order unknown. Default for uninitialized byte swap buffer
    Unknown,

    /// Use native byte order (no encoding necessary).
    Native,

    /// Use Little Endian byte order.  Has no effect on 8-bit streams.
    Little,

    /// Use Big Endian byte order.  Has no effect on 8-bit streams.
    Big
}

template ExpectedWidth(T)
{
    static if(is(T == char))
    {
        alias ExpectedWidth = StreamWidth.UTF8;
    }
    else static if(is(T == wchar))
    {
        alias ExpectedWidth = StreamWidth.UTF16;
    }
    else static if(is(T == dchar))
    {
        alias ExpectedWidth = StreamWidth.UTF32;
    }
    else
    {
        static assert(0, "ExpectedWidth: Unexpected type " ~ (T).stringof);
    }
}

struct TextStreamWindow(BufImpl, IStream, OStream) if(isBuffer!BufImpl && isInputStream!IStream && isOutputStream!OStream)
{
    // Only allow module to instantiate an instance
    private
    {
        this(BufImpl buf, StreamWidth sw = StreamWidth.AUTO)
        {
            _buf = buf;
            _width = sw;
            // by default no input or output stream
        }

        void bindInput(IStream input, ByteOrder ibo = ByteOrder.Native)
        {
            _input = input;
            _ibo = ibo;
        }

        void bindOutput(OStream output, ByteOrder obo = ByteOrder.Native)
        {
            _output = output;
            _obo = obo;
        }
    }

    // returns number of bytes read, these may not all be accessible
    size_t load(size_t toFlush, size_t toLoad = ~0)
    {
        debug writeln("load(", toFlush, ", ", toLoad, ")");
        if(toFlush)
        {
            ubyte[] window = _buf.window;
            if(toFlush > window.length)
                toFlush = window.length;

            // flush some data. We can only flush full code units.
            switch(_width)
            {
            case StreamWidth.AUTO:
                // in this case, we are writing data, so we have no way to detect the data width. Just set it to UTF8.
                _width = StreamWidth.UTF8;
                goto case StreamWidth.UTF8;
            case StreamWidth.UTF8:
                // no need to adjust flush request
                break;
            case StreamWidth.UTF16:
            case StreamWidth.UTF32:
                // only allow multiples of width
                toFlush &= ~(_width-1);
                break;
            default:
                // invalid stream width.
                assert(0);
            }

            auto dataToFlush = window[0..toFlush];
            assert(dataToFlush.length % _width == 0); // ensure we are aligned
            if(_width != StreamWidth.UTF8)
            {
                switch(_obo)
                {
                case ByteOrder.Big:
                    version(LittleEndian)
                    {
                        swapBytes(dataToFlush);
                    }
                    break;
                case ByteOrder.Little:
                    version(BigEndian)
                    {
                        swapBytes(dataToFlush);
                    }
                    break;
                default:
                    // by default, do not swap bytes
                    break;
                }
            }
            // write in a loop until the minimum data is written. Otherwise, we have data that may have been byte-swapped, but hasn't been written.
            // we can't allow access to byte-swapped data.
            // TODO: see if we can just do one write, and keep track of the already-swapped data.
            while(dataToFlush.length > 0)
            {
                auto nwritten = _output.write(dataToFlush);
                if(!nwritten) // eof
                    break;
                dataToFlush = dataToFlush[nwritten..$];
            }
            if(dataToFlush.length > 0)
            {
                // TODO: encountered EOF, do something!
            }

           // update the buffer, letting it know that we don't need the discarded data anymore
           _buf.discard(toFlush);
        }

        // now, read any new data that is requested, minus the overflow
        size_t toRead = void;
        if(toLoad == ~0)
        {
            // special indication that we want to just fill the existing buffer with whatever it can.
            toRead = _buf.capacity - _buf.window.length;
        }
        else
            toRead = toLoad-_overflow_len;
        _buf.extend(toRead);
        debug writeln("toread = ", toRead, " _buf.window = ", _buf.window.length);
        auto nRead = _input.read(_buf.window[$-toRead..$]);
        if(nRead == 0)
        {
            // TODO: handle EOF
        }


        // adjust buffer to exactly encompass only what was read (the value should be a negative number)
        _buf.extend(nRead - toRead);

        // get a pointer to the data just read, plus the overflow data
        auto data = _buf.window[$-nRead-_overflow_len..$];
        debug writeln("read ", nRead, " bytes: ", data);

        // now, process the data
        switch(_width)
        {
        case StreamWidth.AUTO:
            // auto width.  Look for a BOM.  If it's present, use it to
            // decode the byte order and width.
            //
            // note that if the initial data read is less than 4 bytes,
            // there is the potential that BOM won't be detected.  But this
            // possibility is extremely rare.  However, we cannot ignore
            // files that are less than 4 bytes in length.
            if(data.length >= 4)
            {
                if(data[0] == 0xFE && data[1] == 0xFF)
                {
                    debug writeln("determined UTF16 Big Endian");
                    _width = StreamWidth.UTF16;
                    _ibo = ByteOrder.Big;
                    goto case StreamWidth.UTF16;
                }
                else if(data[0] == 0xFF && data[1] == 0xFE)
                {
                    // little endian BOM.
                    _ibo = ByteOrder.Little;
                    if(data[2] == 0 && data[3] == 0)
                    {
                        // most likely this is UTF32
                        debug writeln("determined UTF32 Little Endian");
                        _width = StreamWidth.UTF32;
                        goto case StreamWidth.UTF32;
                    }
                    // utf-16
                    debug writeln("determined UTF16 Little Endian");
                    _width = StreamWidth.UTF16;
                    goto case StreamWidth.UTF16;
                }
                else if(data[0] == 0 && data[1] == 0 && data[2] == 0xFE && data[3] == 0xFF)
                {
                    debug writeln("determined UTF32 Big Endian");
                    _ibo = ByteOrder.Big;
                    _width = StreamWidth.UTF32;
                    goto case StreamWidth.UTF32;
                }
            }
            // else this is utf8, bo is ignored.
            debug writeln("determined UTF8 Big Endian");
            _width = StreamWidth.UTF8;
            break;

        case StreamWidth.UTF8:
            // no decoding necessary.
            break;

        case StreamWidth.UTF16:
            // save any overflow (cannot swap yet because we don't have the other byte)
            _overflow_len = data.length % wchar.sizeof;
            data.length -= _overflow_len;
            version(LittleEndian)
            {
                if(_ibo == ByteOrder.Big)
                    swapBytes(data);
            }
            else
            {
                if(_ibo == ByteOrder.Little)
                    swapBytes(data);
            }
            break;

        case StreamWidth.UTF32:
            // save any overflow (cannot swap yet because we don't have the other bytes)
            _overflow_len = data.length % dchar.sizeof;
            data.length -= _overflow_len;
            version(LittleEndian)
            {
                if(_ibo == ByteOrder.Big)
                    swapBytes(data);
            }
            else
            {
                if(_ibo == ByteOrder.Little)
                    swapBytes(data);
            }
            break;

        default:
            assert(0, "invalid stream width");
        }

        return nRead;
    }

    // returns number of bytes to skip if BOM is discarded
    @property uint discardBOM()
    {
        // first, load data if no data exists
        if(window.length < 4)
            load(0);
        // check for BOM (may be a repeat of check, not sure)
        switch(_width)
        {
        case StreamWidth.UTF8:
            {
                auto data = this.textWindow!char();
                if(data.length >= 3 && data[0] == 0xef && data[1] == 0xbb && data[2] == 0xbf)
                {
                    // discard the BOM
                    return 3;
                }
                break;
            }
        case StreamWidth.UTF16:
            {
                auto data = this.textWindow!wchar();
                if(data[0] == 0xfeff)
                {
                    // discard the BOM
                    return 2;
                }
                break;
            }
        case StreamWidth.UTF32:
            {
                auto data = this.textWindow!dchar();
                if(data[0] == 0xfeff)
                {
                    // discard the BOM
                    return 4;
                }
                break;
            }
        default:
            assert(0, "Invalid width encountered");
        }
        // no BOM encountered
        return 0;
    }

    void close()
    {
        _input.close();
        _output.close();
    }

    ubyte[] window()
    {
        return _buf.window[0..$-_overflow_len];
    }

    T[] textWindow(T = char)() if(is(T == char) || is(T == wchar) || is(T == dchar))
    {
        assert(ExpectedWidth!T is _width);
        return cast(T[])(window());
    }

    ref IStream input() { return _input;}

    ref OStream output() { return _output;}

    ref BufImpl buffer() { return _buf;}

    void reset()
    {
        _buf.reset();
        // reset any overflow length
        _overflow_len = 0;
    }

    @property StreamWidth width()
    {
        return _width;
    }

    @property void width(StreamWidth w)
    {
        if(_width != w)
        {
            assert(w != StreamWidth.AUTO); // cannot set streamwidth to auto mid-stream
            _width = w;
        }
    }

    @property ByteOrder inputByteOrder() const
    {
        return _ibo;
    }

    @property void inputByteOrder(ByteOrder bo) 
    {
        _ibo = bo;
    }

    @property ByteOrder outputByteOrder() const
    {
        return _obo;
    }

    @property void outputByteOrder(ByteOrder bo) 
    {
        _obo = bo;
    }

private:
    // TODO: use simd when possible
    void swapBytes(ubyte[] data)
    in
    {
        assert(_width == wchar.sizeof || _width == dchar.sizeof);
        assert(data.length % _width == 0);
    }
    body
    {
        // depending on the char width, do byte swapping on the data stream.
        switch(_width)
        {
        case wchar.sizeof:
            {
                ushort[] sdata = cast(ushort[])data;
                if((cast(size_t)sdata.ptr & 0x03) != 0)
                {
                    // first two bytes are not aligned, do those specially
                    *sdata.ptr = ((*sdata.ptr << 8) & 0xff00) |
                        ((*sdata.ptr >> 8) & 0x00ff);
                    sdata.popFront();
                }
                // swap every 2 bytes
                // do majority using uint
                // TODO:  see if this can be optimized further, or if there are
                // better options for 64-bit.

                if(sdata.length % 2 != 0)
                {
                    sdata[$-1] = ((sdata[$-1] << 8) & 0xff00) |
                        ((sdata[$-1] >> 8) & 0x00ff);
                    sdata.popBack();
                }
                // rest of the data is 4-byte multiple and aligned
                uint[] idata = cast(uint[])sdata[0..$];
                foreach(ref t; idata)
                {
                    t = ((t << 8) & 0xff00ff00) |
                        ((t >> 8) & 0x00ff00ff);
                }
            }
            break;
        case dchar.sizeof:
            // swap every 4 bytes
            foreach(ref t; cast(uint[])data)
            {
                t = bswap(t);
            }
            break;
        default:
            assert(0, "invalid charwidth");
        }
    }

    BufImpl _buf;
    IStream _input;
    OStream _output;
    ByteOrder _ibo = ByteOrder.Native; // input byte order
    ByteOrder _obo = ByteOrder.Native; // output byte order
    StreamWidth _width;
    ubyte _overflow_len;
}

unittest
{
    static assert(isStreamWindow!(TextStreamWindow!(ArrayBuffer*, NullStream, NullStream)));
}

// constructor functions
auto textInputBuffer(Input, Buffer)(Input i, Buffer b, StreamWidth width = StreamWidth.AUTO, ByteOrder bo = ByteOrder.Native) if(isInputStream!Input && isBuffer!Buffer)
{
    // generate a text stream with an input only.
    alias Stream = TextStreamWindow!(Buffer, Input, InfiniteStream);
    Stream *result = new Stream(b, width);
    result.bindInput(i, bo);
    return result;
}

auto textOutputBuffer(Output, Buffer)(Output o, Buffer b, StreamWidth width = StreamWidth.UTF8, ByteOrder bo = ByteOrder.Native) if(isOutputStream!Output && isBuffer!Buffer)
{
    alias Stream = TextStreamWindow!(Buffer, InfiniteStream, Output);
    Stream *result = new Stream(b, width);
    result.bindOutput(o, bo);
    return result;
}

auto textStreamBuffer(Input, Output, Buffer)(Input i, Output o, Buffer b, StreamWidth width = StreamWidth.AUTO, ByteOrder inputbo = ByteOrder.Native, ByteOrder outputbo = ByteOrder.Native) if(isInputStream!Input && isOutputStream!Output && isBuffer!Buffer)
{
    alias Stream = TextStreamWindow!(Buffer, Input, Output);
    Stream *result = new Stream(b, width);
    result.bindInput(i, inputbo);
    result.bindOutput(o, outputbo);
    return result;
}


// BufferT must be a reference type
struct TextFile(BufferT)
{
    alias InBuffer = TextStreamWindow!(BufferT, IODevice, InfiniteStream);
    alias OutBuffer = TextStreamWindow!(BufferT, InfiniteStream, IODevice);

    enum Mode
    {
        Input,
        Output,
        LockedInput,  // cannot switch
        LockedOutput, // cannot switch
    }

    private
    {
        InBuffer _inbuf;
        OutBuffer _outbuf;
        IODevice _handle;
        Mode _mode;

        // current pointer into the buffer
        size_t bufferIdx;
        // whether to discard the first input BOM bytes or not.
        bool _discardInputBOM = true;
    }

    // bind to a file and a specific buffer
    this(BufferT b, IODevice handle, bool discardInputBOM = true)
    {
        _handle = handle;
        _inbuf = InBuffer(b);
        _inbuf.bindInput(handle);
        _outbuf = OutBuffer(b);
        _outbuf.bindOutput(handle);
        // check the IO device to see what it says
        final switch(handle.openMode)
        {
        case IODevice.OpenMode.Unknown:
        case IODevice.OpenMode.ReadWrite:
            // read/write, default to input
            _mode = Mode.Input;
            break;
        case IODevice.OpenMode.ReadOnly:
            _mode = Mode.LockedInput;
            break;
        case IODevice.OpenMode.WriteOnly:
            _mode = Mode.LockedOutput;
            break;
        }
        _discardInputBOM = discardInputBOM;
    }

    void setWidth(StreamWidth w)
    {
        // set the width of the current mode
        final switch(_mode)
        {
        case Mode.Output:
        case Mode.LockedOutput:
            _outbuf.width = w;
            break;
        case Mode.Input:
        case Mode.LockedInput:
            _inbuf.width = w;
            break;
        }
    }

    void setByteOrder(ByteOrder bo)
    {
        // set the width of the current mode
        final switch(_mode)
        {
        case Mode.Output:
        case Mode.LockedOutput:
            _outbuf.outputByteOrder = bo;
            break;
        case Mode.Input:
        case Mode.LockedInput:
            _inbuf.inputByteOrder = bo;
            break;
        }
    }

    void writeBOM(bool force = false)
    {
        setMode(Mode.Output);
        if(force || (_outbuf.width != StreamWidth.UTF8 && _outbuf.width != StreamWidth.AUTO))
        {
            write(cast(dchar)0xFEFF);
        }
    }

    private void setMode(Mode m)
    {
        if(m != _mode)
        {
            if(_mode & 0x2)
            {
                // cannot switch, it's locked.
                return;
            }

            if((_mode & 0x1) == (m & 0x1))
            {
                // just switching to locked from unlocked.
                _mode = m;
                return;
            }

            // else, switching actual modes. Need to finish up the current mode and start the
            // new mode
            final switch(_mode)
            {
            case Mode.Output:
                // currently in output mode, flush any data written, and reset the buffer
                if(bufferIdx)
                {
                    _outbuf.load(bufferIdx, 0);
                    _outbuf.reset();
                }
                break;
            case Mode.Input:
                // currently in input mode. Need to reposition the actual stream to where the buffer's current index is.
                if(bufferIdx != _inbuf.window.length)
                {
                    // seek back to the current position according to the buffer index
                    _handle.seekCurrent(cast(ptrdiff_t)(bufferIdx - _inbuf.buffer.window.length));
                    _inbuf.reset(); // reset the input buffer.
                }
                break;
            case Mode.LockedInput:
            case Mode.LockedOutput:
                // should not get here, the test above should catch this
                assert(0);
            }
            // switch to new mode
            _mode = m;
            bufferIdx = 0;
            final switch(_mode)
            {
            case Mode.Output:
            case Mode.LockedOutput:
                // ensure the width and byte order are identical
                _outbuf.width = _inbuf.width;
                _outbuf.outputByteOrder = _inbuf.inputByteOrder;
                // extend the buffer to its extents
                _outbuf.load(0);
                break;
            case Mode.Input:
            case Mode.LockedInput:
                // ensure the width and byte order are identical
                _inbuf.width = _outbuf.width;
                _inbuf.inputByteOrder = _outbuf.outputByteOrder;
                break;
            }
        }
    }

    // write data to the stream
    void write(S...)(S args)
    {
        setMode(Mode.Output);
        final switch(_outbuf.width)
        {
        case StreamWidth.AUTO:
            // default to UTF8
            _outbuf.width = StreamWidth.UTF8;
            // fall through
            goto case StreamWidth.UTF8;
        case StreamWidth.UTF8:
            priv_write!(char)(args);
            break;
        case StreamWidth.UTF16:
            priv_write!(wchar)(args);
            break;
        case StreamWidth.UTF32:
            priv_write!(dchar)(args);
            break;
        }
    }

    private void priv_write(C, S...)(S args)
    {
        auto w = OutputRange!(C)(this);
        foreach(arg; args)
        {
            alias A = typeof(arg);
            static if(isSomeString!A)
            {
                w.put(arg);
            }
            else static if (isIntegral!A)
            {
                toTextRange(arg, w);
            }
            else static if (is(A : char) || isSomeChar!A)
            {
                w.put(arg);
            }
            else
            {
                // Most general case
                std.format.formattedWrite(w, "%s", arg);
            }
        }
    }

    // only call this while in output mode.
    private void put(const(ubyte)[] d)
    in
    {
        assert(_mode == Mode.Output || _mode == Mode.LockedOutput);
    }
    body
    {
        // put the given bytes into the buffer, loading until done
        debug writeln("inside put, d = ", d);
        if(d.length)
        {
            while(true)
            {
                ubyte[] target = _outbuf.window[bufferIdx..$];
                auto towrite = d.length;
                if(towrite > target.length)
                {
                    towrite = target.length;
                }
                target[0..towrite] = d[0..towrite];
                bufferIdx += towrite;
                d = d[towrite..$];
                if(d.length)
                    // still data left
                    flush();
                else
                    // exit loop
                    break;
            }
        }
    }

    void flush()
    {
        if((_mode & 0x1) == Mode.Output)
        {
            // flush all written data, and ensure the buffer is as full as possible
            _outbuf.load(bufferIdx);
        }
        // else, input mode. Do nothing
    }

    private struct OutputRange(CT)
    {
        TextFile *output;

        this(ref TextFile output)
        {
            this.output = &output;
        }

        void put(A)(A writeme) if(is(ElementType!A : const(dchar)))
        {
            static if(isSomeString!A)
                alias typeof(writeme[0]) C;
            else
                alias ElementType!A C;
            static assert(!is(C == void));
            static if(C.sizeof == CT.sizeof)
            {
                // width is the same size as the stream itself, just paste the text
                // into the stream.
                output.put((cast(const(ubyte)*) writeme.ptr)[0..writeme.length * CT.sizeof]);
            }
            else
            {
                static if(is(C : const(char)))
                {
                    // this is a char[] array.
                    dchar val = void;
                    auto ptr = writeme.ptr;
                    auto eptr = writeme.ptr + writeme.length;
                    uint multi = 0;
                    while(ptr != eptr)
                    {
                        char data = *ptr++;
                        if(data & 0x80)
                        {
                            if(!multi)
                            {
                                // determine highest 0 bit
                                multi = 6 - bsr((~data) & 0xff);
                                if(multi == 0)
                                    throw new Exception("invalid utf sequence");
                                val = data & ~(0xffff_ffc0 >> multi);
                            }
                            else if(data & 0x40)
                                throw new Exception("invalid utf sequence");
                            else
                            {
                                val = (val << 6) | (data & 0x3f);
                                if(!--multi)
                                {
                                    // process this dchar
                                    put(val);
                                }
                            }
                        }
                        else
                        {
                            if(multi)
                                throw new Exception("invalid utf sequence");
                            put(cast(CT)data);
                        }
                    }
                    if(multi)
                        throw new Exception("invalid utf sequence");
                }
                else static if(is(C : const(wchar)))
                {
                    auto ptr = writeme.ptr;
                    auto end = writeme.ptr + writeme.length;
                    while(ptr != end)
                    {
                        wchar data = *ptr++;
                        if((data & 0xF800) == 0xD800)
                        {
                            // part of a surrogate pair
                            if(data > 0xDBFF || ptr == end)
                                throw new Exception("invalid utf sequence");
                            dchar val = (data & 0x3ff) << 10;
                            data = *ptr++;
                            if(data > 0xDFFF || data < 0xDC00)
                                throw new Exception("invalid utf sequence");
                            val = (val | (data & 0x3ff)) + 0x10000;
                            put(val);
                        }
                        else
                        {
                            // not specially encoded
                            put(cast(dchar)data);
                        }
                    }
                }
                else
                {
                    // just dchars, put each one.
                    foreach(dc; writeme)
                    {
                        put(dc);
                    }
                }
            }
        }

        void put(A)(A c) if(is(A : const(dchar)))
        {
            static if(A.sizeof == CT.sizeof)
            {
                // output the data directly to the output stream
                output.put((cast(const(ubyte) *)&c)[0..CT.sizeof]);
            }
            else
            {
                static if(is(CT == char))
                {
                    static if(is(A : const(wchar)))
                    {
                        // A is a wchar.  Make sure it's not a surrogate pair
                        // (that it's a valid dchar)
                        if(!isValidDchar(c))
                            throw new Exception("invalid character output");
                    }
                    // convert the character to utf8
                    if(c <= 0x7f)
                    {
                        ubyte buf = cast(ubyte)c;
                        output.put((&buf)[0..1]);
                    }
                    else
                    {
                        ubyte[4] buf = void;
                        auto idx = 3;
                        auto mask = 0x3f;
                        dchar c2 = c;
                        while(c2 > mask)
                        {
                            buf[idx--] = 0x80 | (c2 & 0x3f);
                            c2 >>= 6;
                            mask >>= 1;
                        }
                        buf[idx] = (c2 | (~mask << 1)) & 0xff;
                        output.put(buf.ptr[idx..buf.length]);
                    }
                }
                else static if(is(CT == wchar))
                {
                    static if(is(A : const(char)))
                    {
                        // this is a utf-8 character, only works if it's an
                        // ascii character
                        if(c > 0x7f)
                            throw new Exception("invalid character output");
                    }
                    // convert the character to utf16
                    wchar[2] buf = void;
                    assert(isValidDchar(c));
                    if(c < 0xFFFF)
                    {
                        buf[0] = cast(wchar)c;
                        output.put((cast(ubyte*)buf.ptr)[0..wchar.sizeof]);
                    }
                    else
                    {
                        dchar dc = c - 0x10000;
                        buf[0] = cast(wchar)(((dc >> 10) & 0x3FF) + 0xD800);
                        buf[1] = cast(wchar)((dc & 0x3FF) + 0xDC00);
                        output.put((cast(ubyte*)buf.ptr)[0..wchar.sizeof * 2]);
                    }
                }
                else static if(is(CT == dchar))
                {
                    static if(is(A : const(char)))
                    {
                        // this is a utf-8 character, only works if it's an
                        // ascii character
                        if(c > 0x7f)
                            throw new Exception("invalid character output");
                    }
                    else static if(is(A : const(wchar)))
                    {
                        // A is a wchar.  Make sure it's not a surrogate pair
                        // (that it's a valid dchar)
                        if(!isValidDchar(c))
                            throw new Exception("invalid character output");
                    }
                    // converting to utf32, just write directly
                    dchar dc = c;
                    output.put((cast(ubyte*)&dc)[0..dchar.sizeof]);
                }
                else
                    static assert(0, "invalid types used for output stream, " ~ CT.stringof ~ ", " ~ C.stringof);
            }
        }
    }

    void close()
    {
        // flush and close
        flush();
        
        destroy(_handle);
        destroy(_inbuf);
        destroy(_outbuf);
    }

    // input TODO: skip should seek forward if nbytes is not in buffer.
    size_t skip(size_t nbytes)
    {
        if((_mode & 0x1) == Mode.Output)
        {
            setMode(Mode.Input);
            _inbuf.load(0);
        }
        if(nbytes > _inbuf.window.length)
            nbytes = _inbuf.window.length;
        bufferIdx += nbytes;
        return nbytes;
    }

    private struct InputRange(CT)
    {
        private
        {
            TextFile *input;
            size_t curlen;
            dchar cur;
        }

        this(ref TextFile di)
        {
            this.input = &di;
            popFront();
        }

        public @property bool empty()
        {
            return !curlen;
        }

        public @property dchar front()
        {
            return cur;
        }
        
        private CT[] window()
        {
            return input._inbuf.textWindow!(CT)[(input.bufferIdx / CT.sizeof)..$];
        }

        public void popFront()
        {
            input.skip(curlen);
            curlen = 0;
            while(true)
            {
                if(parseDChar(window))
                    break;
                if(!input._inbuf.load(0))
                    break;
            }
        }

        // returns true if a character was parsed
        private bool parseDChar(const(CT)[] data)
        {
            if(!data.length)
                return false;

            // try to treat the start of data like it's a CT[] sequence, see if
            // there is a valid code point.
            static if(is(CT == char))
            {
                if(data[0] & 0x80)
                {
                    auto len = 7 - bsr((~data[0]) & 0xff);
                    if(len < 2 || len > 4)
                        throw new Exception("Invalid utf sequence");
                    if(len > data.length)
                    {
                        // couldn't get a complete character.
                        return false;
                    }
                    else
                    {
                        // got the data, now, parse it
                        // enforce that the remaining bytes all start with 10b
                        foreach(i; 1..len)
                            if((data[i] & 0xc0) != 0x80)
                                throw new Exception("invalid utf sequence");
                        curlen = len;
                        switch(len)
                        {
                        case 2:
                            cur = ((data[0] & 0x1f) << 5) | 
                                (data[1] & 0x3f);
                            return true;
                        case 3:
                            cur = ((data[0] & 0x0f) << 11) | 
                                ((data[1] & 0x3f) << 6) |
                                (data[2] & 0x3f);
                            return true;
                        case 4:
                            cur = ((data[0] & 0x07) << 17) | 
                                ((data[1] & 0x3f) << 12) |
                                ((data[2] & 0x3f) << 6) |
                                (data[3] & 0x3f);
                            return true;
                        default:
                            assert(0); // should never happen
                        }
                    }
                }
                else
                {
                    cur = data[0];
                    curlen = 1;
                    return true;
                }
            }
            else static if(is(CT == wchar))
            {
                cur = data[0];
                if(cur < 0xD800 || cur >= 0xE000)
                {
                    curlen = wchar.sizeof;
                    return true;
                }
                else if(cur >= 0xDCFF)
                {
                    // second half of surrogate pair, invalid.
                    throw new Exception("invalid UTF sequence");
                }
                else if(data.length < 2)
                {
                    // surrogate pair, but not enough space for the second
                    // wchar
                    return false;
                }
                else if(data[1] < 0xDC00 || data[1] >= 0xE000)
                {
                    throw new Exception("invalid UTF sequence");
                }
                else
                {
                    // combine the pairs
                    cur = (((cur & 0x3FF) << 10) | (data[1] & 0x3FF)) + 0x10000;
                    curlen = wchar.sizeof * 2;
                    return true;
                }
            }
            else // dchar
            {
                cur = data[0];
                curlen = 4;
                return true;
            }
        }
    }

    // call before any read command, to automatically switch to input mode, and discard any BOM that may be
    // needed.
    private void processBOM()
    {
        setMode(Mode.Input);
        if(_discardInputBOM)
        {
            bufferIdx += _inbuf.discardBOM();
            _discardInputBOM = false;
        }
    }

    /**
     * Formatted read.
     * TODO: fill out this doc
     */
    public uint readf(Data...)(in char[] format, Data data)
    {
        processBOM();
        switch(_inbuf.width)
        {
        case StreamWidth.UTF8:
            {
                auto ir = InputRange!char(this);
                return formattedRead(ir, format, data);
            }
        case StreamWidth.UTF16:
            {
                auto ir = InputRange!wchar(this);
                return formattedRead(ir, format, data);
            }
        case StreamWidth.UTF32:
            {
                auto ir = InputRange!dchar(this);
                return formattedRead(ir, format, data);
            }
        default:
            assert(0); // should not get here
        }
    }
}

TextFile!(ArrayBuffer*)* openTextFile(string fname, string mode)
{
    alias ReturnType = TextFile!(ArrayBuffer*);
    auto buf = ArrayBuffer.allocateDefault();
    auto device = new IODevice(fname, mode);
    return new ReturnType(buf, device);
}
