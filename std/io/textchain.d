// define processors needed to create a text-based buffer chain

module std.io.textchain;
import std.io.bufchain;
import std.array;
import core.bitop;

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

// TODO: use simd when possible
// TODO: handle generic multi-ranges of ubyte[] here
private void swapBytes(StreamWidth width, R)(R data) if ((width == StreamWidth.UTF16 || width == StreamWidth.UTF32) && is(R == ubyte[]))
in
{
    assert(data.length % width == 0);
}
body
{
    // depending on the char width, do byte swapping on the data stream.
    static if(width == StreamWidth.UTF16)
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
    else
    {
        // swap every 4 bytes
        foreach(ref t; cast(uint[])data)
        {
            t = bswap(t);
        }
    }
}

// buffer processor that deals with decoding text data (including processing
// BOMs).
struct TextDecoder(string streamStateName = null)
{
    private ref streamState(BRef)(BRef b)
    {
        static if(streamStateName == null)
            return b.context;
        else
            return mixin("b.context." ~ streamStateName);
    }

    void processBuf(BufRef)(BufRef b)
    {
        // process all of the data we can
        auto data = b.window;
        switch(streamState(b).width)
        {
            static if(is(typeof(streamState(b).width = StreamWidth.UTF8)))
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
                        streamState(b).width = StreamWidth.UTF16;
                        streamState(b).inputByteOrder = ByteOrder.Big;

                        // set the matching output byte order
                        static if(is(typeof(streamState(b).outputByteOrder)))
                            streamState(b).outputByteOrder = ByteOrder.Big;
                        goto case StreamWidth.UTF16;
                    }
                    else if(data[0] == 0xFF && data[1] == 0xFE)
                    {
                        // little endian BOM.
                        streamState(b).inputByteOrder = ByteOrder.Little;

                        // set the matching output byte order
                        static if(is(typeof(streamState(b).outputByteOrder)))
                            streamState(b).outputByteOrder = ByteOrder.Little;
                        if(data[2] == 0 && data[3] == 0)
                        {
                            // most likely this is UTF32
                            debug writeln("determined UTF32 Little Endian");
                            streamState(b).width = StreamWidth.UTF32;
                            goto case StreamWidth.UTF32;
                        }
                        // utf-16
                        debug writeln("determined UTF16 Little Endian");
                        streamState(b).width = StreamWidth.UTF16;
                        goto case StreamWidth.UTF16;
                    }
                    else if(data[0] == 0 && data[1] == 0 && data[2] == 0xFE && data[3] == 0xFF)
                    {
                        debug writeln("determined UTF32 Big Endian");
                        streamState(b).inputByteOrder = ByteOrder.Big;

                        // set the matching output byte order.
                        static if(is(typeof(streamState(b).outputByteOrder)))
                            streamState(b).outputByteOrder = ByteOrder.Big;
                        streamState(b).width = StreamWidth.UTF32;
                        goto case StreamWidth.UTF32;
                    }
                }
                // else this is utf8, bo is ignored.
                debug writeln("determined UTF8 Big Endian");
                streamState(b).width = StreamWidth.UTF8;
                break;
            }

        case StreamWidth.UTF8:
            // no decoding necessary.
            break;

        case StreamWidth.UTF16:
            // only can decode multiples of 2 bytes
            data.length -= data.length % wchar.sizeof;
            data = data[0 .. $ - $ % wchar.sizeof];
            version(LittleEndian)
            {
                if(streamState(b).inputByteOrder == ByteOrder.Big)
                    swapBytes!(StreamWidth.UTF16)(data);
            }
            else
            {
                if(streamState(b).inputByteOrder == ByteOrder.Little)
                    swapBytes!(StreamWidth.UTF16)(data);
            }
            break;

        case StreamWidth.UTF32:
            // can only decode multiples of 4 bytes.
            data = data[0 .. $ - $ % dchar.sizeof];
            version(LittleEndian)
            {
                if(streamState(b).inputByteOrder == ByteOrder.Big)
                    swapBytes!(StreamWidth.UTF32)(data);
            }
            else
            {
                if(streamState(b).inputByteOrder == ByteOrder.Little)
                    swapBytes!(StreamWidth.UTF32)(data);
            }
            break;

        default:
            // invalid stream width
            assert(0);
        }

        // release decoded data to next processor
        b.release(data.length);
    }
}

struct TextEncoder(string streamStateName = null)
{
    private ref streamState(BRef)(BRef b)
    {
        static if(streamStateName == null)
            return b.context;
        else
            return mixin("b.context." ~ streamStateName);
    }


    void processBuf(BufRef)(BufRef b)
    {
        // process all of the data we can
        auto data = b.window;
        switch(streamState(b).width)
        {
            static if(is(typeof(streamState(b).width = StreamWidth.UTF8)))
            {
            case StreamWidth.AUTO:
                // in this case, we are writing data, so we have no way to detect the data width. Just set it to UTF8.
                streamState(b).width = StreamWidth.UTF8;
                goto case StreamWidth.UTF8;
            }

        case StreamWidth.UTF8:
            // no adjustments necessary, just release all the data
            b.release(data.length);
            return;

        case StreamWidth.UTF16:
        case StreamWidth.UTF32:
            // only allow multiples of width
            data.length -= data.length % streamState(b).width;
            break;
        default:
            // invalid stream width.
            assert(0);
        }

        assert(streamState(b).width != StreamWidth.UTF8); // utf8 should be handled above
        version(LittleEndian)
        {
            if(streamState(b).outputByteOrder == ByteOrder.Big)
            {
                if(streamState(b).width == StreamWidth.UTF16)
                    swapBytes!(StreamWidth.UTF16)(data);
                else
                    swapBytes!(StreamWidth.UTF32)(data);
            }
        }
        else
        {
            if(streamState(b).outputByteOrder == ByteOrder.Little)
            {
                if(streamState(b).width == StreamWidth.UTF16)
                    swapBytes!(StreamWidth.UTF16)(data);
                else
                    swapBytes!(StreamWidth.UTF32)(data);
            }
        }

        // release encoded data to next processor
        b.release(data.length);
    }
}

struct DelimiterChecker(T)
{
    size_t elementsChecked;
    T delim;

    void processBuf(BRef)(BRef bref)
    {
        // look for the delimiter
        bool done = false;
        foreach(i, T elem; bref.window[elementsChecked..$])
        {
            if(done == true)
            {
                bref.release(elementsChecked + i);
                elementsChecked = 0;
                return;
            }
            else if(elem == delim)
            {
                done = true;
            }
        }
        // else, could not find anything
        elementsChecked = bref.window.length;
    }

    void finish()
    {
        elementsChecked = 0;
    }
}

// buffer reference wrapper to convert buffer data to character data
struct TextBufRef(BRef, Char)
{
    BRef bref;
    auto window()
    {
        auto win = bref.window;
        immutable extraBytes = win.length % Char.sizeof;
        return cast(Char[])win[0..$-extraBytes];
    }

    void release(size_t numElements)
    {
        bref.release(numElements * Char.sizeof);
    }

    size_t request(size_t minNewCharacters, size_t maxNewCharacters = 0)
    {
        // check for extra bytes
        immutable extraBytes = bref.window.length % Char.sizeof; 
        auto result = bref.request(minNewCharacters * Char.sizeof - extraBytes, maxNewCharacters * Char.sizeof - extraBytes);
        return (result + extraBytes) / Char.sizeof;
    }

    static if(__traits(hasMember, BRef, "upstreamProcessor"))
    {
        auto upstreamProcessor()
        {
            return bref.upstreamProcessor();
        }
    }

    static if(__traits(hasMember, BRef, "downstreamProcessor"))
    {
        auto downstreamProcessor()
        {
            return bref.downstreamProcessor;
        }
    }

    static if(__traits(hasMember, BRef, "context"))
    {
        ref context()
        {
            return bref.context;
        }
    }
}

struct TextBufferProcessor(WrappedProcessor, StreamWidth _width = StreamWidth.AUTO, string streamStateName = null)
{
    WrappedProcessor subProc;

    static if(_width == StreamWidth.AUTO)
    {
        auto ref width(BRef)(BRef bref)
        {
            static if(streamStateName == null)
                return bref.context.width;
            else
                return mixin("bref.context." ~ streamStateName ~ ".width");
        }
    }
    else
    {
        // stream width is predefined
        alias width = _width;
    }

    static if(__traits(hasMember, WrappedProcessor, "reset"))
    {
        auto reset() 
        {
            return subProc.reset();
        }
    }

    static if(__traits(hasMember, WrappedProcessor, "processBuf"))
    {
        auto processBuf(BRef)(BRef bref)
        {
            static if(_width == StreamWidth.AUTO)
            {
                immutable w = width(bref);
            }
            else
            {
                alias w = _width;
            }

            switch(w)
            {
            case StreamWidth.UTF8:
                return subProc.processBuf(TextBufRef!(BRef, char)(bref));
            case StreamWidth.UTF16:
                return subProc.processBuf(TextBufRef!(BRef, wchar)(bref));
            case StreamWidth.UTF32:
                return subProc.processBuf(TextBufRef!(BRef, dchar)(bref));
            default:
                assert(0); // should never be called with auto width
            }
        }
    }

    static if(__traits(hasMember, WrappedProcessor, "request"))
    {
        auto request(BRef)(BRef bref, size_t minNewSpace, size_t maxNewSpace)
        {
            // need to convert to the proper width
            static if(_width == StreamWidth.AUTO)
            {
                immutable w = width(bref);
            }
            else
            {
                alias w = _width;
            }

            // note, we need to consider that the requestor wants x bytes, but we only work in
            // characters. So we must round up to the next character for both min and max.
            switch(w)
            {
            case StreamWidth.UTF8:
                return subProc.request(TextBufRef!(BRef, char)(bref), minNewSpace, maxNewSpace);
            case StreamWidth.UTF16:
                return subProc.request(TextBufRef!(BRef, wchar)(bref),
                                     (minNewSpace + wchar.sizeof - 1) / wchar.sizeof,
                                     (maxNewSpace + wchar.sizeof - 1) / wchar.sizeof) * wchar.sizeof;
            case StreamWidth.UTF32:
                return subProc.request(TextBufRef!(BRef, dchar)(bref),
                                     (minNewSpace + dchar.sizeof - 1) / dchar.sizeof,
                                     (maxNewSpace + dchar.sizeof - 1) / dchar.sizeof) * dchar.sizeof;
            default:
                assert(0); // should never be called with auto width
            }
        }
    }
}

// byline processor
struct ByLine(Char, BufImpl, InputStream, StreamWidth defaultWidth=StreamWidth.AUTO, ByteOrder defaultByteOrder = ByteOrder.Native)
{
    private
    {
        struct TextStreamState
        {
            static if(defaultWidth == StreamWidth.AUTO)
            {
                StreamWidth width = defaultWidth;
                ByteOrder inputByteOrder = defaultByteOrder;
            }
            else
            {
                enum width = defaultWidth;
                enum inputByteOrder = defaultByteOrder;
            }
        }

        struct LineWindow
        {
            // release the data that's been used.
            void doRelease(B)(B bref)
            {
                bref.release(bref.window.length);
            }

            auto data(C, B)(B bref)
            {
                // TODO: need to figure out a way to cast this generically in the case of non-array buffer type.
                return cast(C[])bref.window;
            }

            auto empty(B)(B bref)
            {
                return bref.window.length == 0;
            }
        }

        import std.meta;
        BufChain!(BufImpl, TextStreamState, InputAdapter!InputStream, TextDecoder!(), TextBufferProcessor!(DelimiterChecker!dchar), LineWindow) inputChain;
        Char[] curLine;

        static if(defaultWidth == StreamWidth.AUTO)
            auto width() { return inputChain.context.width; }
        else
            alias width = defaultWidth;
    }

    this(BufImpl buffer, InputStream input, dchar delim = '\n')
    {
        // initialize all the components of the chain
        inputChain.bufImpl = buffer;
        inputChain.procs[0] = InputAdapter!InputStream(input);
        inputChain.procs[2].subProc.delim = delim;
        popFront();
    }

    // everything should be set up here
    Char[] front()
    {
        return curLine;
    }

    void popFront()
    {
        import std.conv: to;
        // search for the next line
        auto lineWindow = inputChain.getProc!(3);
        lineWindow.doRelease;
        while(lineWindow.empty)
        {
            if(!inputChain.underflow!3())
            {
                // no more data available, flush whatever is in the buffer without a delimiter
                auto checkerBuf = inputChain.getRef!(2);
                checkerBuf.release(checkerBuf.window.length);
                inputChain.procs[2].subProc.finish();
                break;
            }
        }

        if(lineWindow.empty)
            curLine = null;
        else
        {
            // construct the current line. This may need translation.
            switch(inputChain.context.width)
            {
            case StreamWidth.UTF8:
                static if(Char.sizeof == StreamWidth.UTF8)
                    curLine = lineWindow.data!Char;
                else
                    curLine = to!(Char[])(lineWindow.data!char);
                break;
            case StreamWidth.UTF16:
                static if(Char.sizeof == StreamWidth.UTF16)
                    curLine = lineWindow.data!Char;
                else
                    curLine = to!(Char[])(lineWindow.data!wchar);
                break;
            case StreamWidth.UTF32:
                static if(Char.sizeof == StreamWidth.UTF32)
                    curLine = lineWindow.data!Char;
                else
                    curLine = to!(Char[])(lineWindow.data!dchar);
                break;
            default:
                assert(0); // this should never happen
            }
        }
    }

    bool empty()
    {
        // we are empty if the current line is empty.
        return curLine.length == 0;
    }
}

auto byLine(Char, StreamWidth defaultWidth=StreamWidth.AUTO, ByteOrder defaultByteOrder = ByteOrder.Native, BufImpl, InputStream)(InputStream inputStream, BufImpl bufImpl)
{
    return ByLine!(Char, BufImpl, InputStream, defaultWidth, defaultByteOrder)(bufImpl, inputStream);
}

auto byLine(Char,  StreamWidth defaultWidth=StreamWidth.AUTO, ByteOrder defaultByteOrder = ByteOrder.Native, InputStream)(InputStream inputStream)
{
    import std.io.buffer; // for arraybuffer
    return byLine!(Char, defaultWidth, defaultByteOrder)(inputStream, new ArrayBuffer);
}

/*struct TextOutput(BufImpl, OutputStream, StreamWidth defaultWidth=StreamWidth.UTF8, ByteOrder defaultByteOrder = ByteOrder.Native)
{
    private
    {
        struct TextStreamState
        {
            enum _width = defaultWidth;
            enum _outputBO = defaultByteOrder;
        }

        BufChain!(BufImpl, size_t, TextEncoder!TextStreamState, OutputAdapter!OutputStream) outputChain;
    }

    this(BufImpl buffer, OutputStream output)
    {
        // initialize all the components of the chain
        outputChain.bufImpl = buffer;
        outputChain.procs[2] = OutputAdapter!OutputStream(output);
    }

    auto format(T...)(T values)
    {

    }
}
*/

// a sibling pointer points to another piece of data inside the same memory block.
// it survives moves :)
struct SPtr(T)
{
    ptrdiff_t _offset;
    void opAssign(T* orig) { offset = cast(void *)orig - cast(void *)&this;}
    this(T *orig) {this = orig;}
    inout(T) *_get() inout { return cast(inout(T)*)((cast(inout(void) *)&this) + _offset);}
    alias _get this;
}


// Text file with InputStream and OutputStream types. This is a suitable
// stand-in for stdio.File.
/+struct TextFile(BufImpl, InputStream, OutputStream)
{
    private
    {
        struct TextStreamState
        {
            StreamWidth _width = StreamWidth.AUTO;
            ByteOrder _inputBO = ByteOrder.Native;
            ByteOrder _outputBO = ByteOrder.Native;
        }

        BufChain!(BufImpl, InputStream, TextDecoder!TextStreamState, size_t) inputChain;
        BufChain!(SPtr!BufImpl, size_t, TextEncoder!(SPtr!TextStreamState), OutputStream) outputChain;
        
        bool inputMode;

        // use private accessors to access elements of the stream we care about instead of using direct tuple syntax.
        ref state()
        {
            return inputDecoder._state;
        }

        ref buffer()
        {
            return inputChain.bufImpl;
        }

        auto inputWindow()
        {
            return inputChain.getRef!(2).window;
        }

        auto outputWindow()
        {
            return outputChain.getRef!(0).window;
        }
        
        ref inputDecoder()
        {
            return inputChain.procs[1];
        }
        
        ref outputEncoder()
        {
            return outputChain.procs[1];
        }
        
        ref input()
        {
            return inputChain.procs[0];
        }
        
        ref output()
        {
            return outputChain.procs[$-1];
        }
    }

    this(InputStream istream, OutputStream ostream)
    {
        // need to have the two buffer chains share state.
        outputChain.bufImpl = &inputChain.bufImpl;
        outputEncoder._state = &state();
        
        // set the input and output stream types
        input = istream;
        output = ostream;
    }
    
    /**
     * Get the buffer being used by the stream.
     */
    Char[] buffer(Char)()
    {
        assert(state._width == sizeof(Char));
        
        if(inputMode)
            return cast(Char[])inputWindow.window;
        else
            return cast(Char[])outputWindow.window;
    }
    
    /**
     * Get the position of the beginning of the buffer in the file, if applicable
     */
    static if(hasMember!(InputStream, "tell") && hasMember!(OutputStream, "tell"))
    {
        ulong tell()
        {
            if(inputMode)
                return input.tell - (inputChain.pos[0] - )
        }
    }
}+/
