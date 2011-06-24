/**
Standard I/O functions that extend $(B std.c.stdio).  $(B std.c.stdio)
is $(D_PARAM public)ally imported when importing $(B std.stdio).

Source: $(PHOBOSSRC std/_stdio.d)
Macros:
WIKI=Phobos/StdStdio

Copyright: Copyright Digital Mars 2007-.
License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors:   $(WEB digitalmars.com, Walter Bright),
           $(WEB erdani.org, Andrei Alexandrescu),
           Steven Schveighoffer
 */
module std.stdio;
import std.format;
import std.string;
import core.memory, core.stdc.errno, core.stdc.stddef, core.stdc.stdlib,
    core.stdc.string, core.stdc.wchar_;
import std.traits;
import std.range;
import std.utf;
import std.conv;

version (DigitalMars) version (Windows)
{
    // Specific to the way Digital Mars C does stdio
    version = DIGITAL_MARS_STDIO;
    import std.c.stdio : __fhnd_info, FHND_WCHAR, FHND_TEXT;
}

version (Posix)
{
    import core.sys.posix.stdio;
    import core.sys.posix.fcntl;
    import core.sys.posix.unistd;
    alias core.sys.posix.stdio.fileno fileno;
}

version (linux)
{
    // Specific to the way Gnu C does stdio
    version = GCC_IO;
    extern(C) FILE* fopen64(const char*, const char*);
}

version (OSX)
{
    version = GENERIC_IO;
    alias core.stdc.stdio.fopen fopen64;
}

version (FreeBSD)
{
    version = GENERIC_IO;
    alias core.stdc.stdio.fopen fopen64;
}

version(Windows)
{
    alias core.stdc.stdio.fopen fopen64;
}

version (DIGITAL_MARS_STDIO)
{
    extern (C)
    {
        /* **
         * Digital Mars under-the-hood C I/O functions.
         * Use _iobuf* for the unshared version of FILE*,
         * usable when the FILE is locked.
         */
        int _fputc_nlock(int, _iobuf*);
        int _fputwc_nlock(int, _iobuf*);
        int _fgetc_nlock(_iobuf*);
        int _fgetwc_nlock(_iobuf*);
        int __fp_lock(FILE*);
        void __fp_unlock(FILE*);

        int setmode(int, int);
    }
    alias _fputc_nlock FPUTC;
    alias _fputwc_nlock FPUTWC;
    alias _fgetc_nlock FGETC;
    alias _fgetwc_nlock FGETWC;

    alias __fp_lock FLOCK;
    alias __fp_unlock FUNLOCK;

    alias setmode _setmode;
    enum _O_BINARY = 0x8000;
    int _fileno(FILE* f) { return f._file; }
    alias _fileno fileno;
}
else version (GCC_IO)
{
    /* **
     * Gnu under-the-hood C I/O functions; see
     * http://gnu.org/software/libc/manual/html_node/I_002fO-on-Streams.html
     */
    extern (C)
    {
        int fputc_unlocked(int, _iobuf*);
        int fputwc_unlocked(wchar_t, _iobuf*);
        int fgetc_unlocked(_iobuf*);
        int fgetwc_unlocked(_iobuf*);
        void flockfile(FILE*);
        void funlockfile(FILE*);
        ssize_t getline(char**, size_t*, FILE*);
        ssize_t getdelim (char**, size_t*, int, FILE*);

        private size_t fwrite_unlocked(const(void)* ptr,
                size_t size, size_t n, _iobuf *stream);
    }

    version (linux)
    {
        // declare fopen64 if not already
        static if (!is(typeof(fopen64)))
            extern (C) FILE* fopen64(in char*, in char*);
    }

    alias fputc_unlocked FPUTC;
    alias fputwc_unlocked FPUTWC;
    alias fgetc_unlocked FGETC;
    alias fgetwc_unlocked FGETWC;

    alias flockfile FLOCK;
    alias funlockfile FUNLOCK;
}
else version (GENERIC_IO)
{
    extern (C)
    {
        void flockfile(FILE*);
        void funlockfile(FILE*);
    }

    int fputc_unlocked(int c, _iobuf* fp) { return fputc(c, cast(shared) fp); }
    int fputwc_unlocked(wchar_t c, _iobuf* fp)
    {
        return fputwc(c, cast(shared) fp);
    }
    int fgetc_unlocked(_iobuf* fp) { return fgetc(cast(shared) fp); }
    int fgetwc_unlocked(_iobuf* fp) { return fgetwc(cast(shared) fp); }

    alias fputc_unlocked FPUTC;
    alias fputwc_unlocked FPUTWC;
    alias fgetc_unlocked FGETC;
    alias fgetwc_unlocked FGETWC;

    alias flockfile FLOCK;
    alias funlockfile FUNLOCK;
}
else
{
    static assert(0, "unsupported C I/O system");
}

/**
 * Seek anchor.  Used when telling a seek function which anchor to seek from
 */
enum Anchor
{
    /**
     * Seek from the beginning of the stream
     */
    Begin = 0,

    /**
     * Seek from the current position of the stream
     */
    Current = 1,

    /**
     * Seek from the end of the stream.
     */
    End = 2
}

enum PAGE = 4096;

/**
 * Interface defining seekable streams
 */
interface Seek
{
    /**
     * Seek the stream.
     *
     * Note, this throws an exception if seeking fails or isn't supported.
     *
     * params:
     * delta = the number of bytes to seek from the given anchor
     * whence = from whence to seek.  If this is Anchor.begin, the stream is
     * seeked to the given file position starting at the beginning of the file.
     * If this is Anchor.Current, then delta is treated as an offset from the
     * current position.  If this is Anchor.End, then the stream is seeked from
     * the end of the stream.  For End, delta should always be negative.
     *
     * returns: The position of the stream from the beginning of the stream
     * after seeking, or ~0 if this cannot be determined.
     */
    ulong seek(long delta, Anchor whence=Anchor.Begin);

    /**
     * Determine the current file position.
     *
     * Returns ~0 if the operation fails or is not supported.
     */
    final ulong tell() {return seek(0, Anchor.Current); }

    /**
     * returns: false if the stream cannot be seeked, true if it can.  True
     * does not mean that a given seek call will succeed.
     */
    @property bool seekable() const;
}

/**
 * An input stream.  This is the simplest interface to a stream.  An
 * InputStream provides no buffering or high-level constructs, it's simply an
 * abstraction of a low-level stream mechanism.
 */
interface InputStream : Seek
{
    /**
     * Read data from the stream.
     *
     * Throws an exception if reading does not succeed.
     *
     * params: data = Location to store the data from the stream.  Only the
     * data read from the stream is filled in.  It is valid for read to return
     * less than the number of bytes requested *and* not be at EOF.
     *
     * returns: 0 on EOF, number of bytes read otherwise.
     */
    size_t read(ubyte[] data);

    /**
     * Close the stream.  This releases any resources from the object.
     */
    void close();
}

interface BufferedInput : Seek
{
    /**
     * Read data from the stream.
     *
     * Throws an exception if reading does not succeed.
     *
     * params: data = Location to store the data from the stream.  Only the
     * data read from the stream is filled in.  It is valid for read to return
     * less than the number of bytes requested *and* not be at EOF.
     *
     * returns: 0 on EOF, number of bytes read otherwise.
     */
    size_t read(ubyte[] data);
    
    /**
     * Read a line from the stream.  Optionally you can give a line terminator
     * other than '\n'
     *
     * Note that this does not take into account encoding of the file.  So if
     * the file is encoded as UTF-16 text, this may not return a valid line.  
     *
     * The lineterm argument is treated as a binary encoding of the stream's
     * data.  Note that some streams -- C streams in particular -- may be
     * inefficient if you do more than one element in lineterm.
     */
    const(ubyte)[] readln(const(ubyte)[] lineterm);
    /// ditto
    final const(ubyte)[] readln(ubyte lineterm = '\n')
    {
        return readln((&lineterm)[0..1]);
    }

    /**
     * Close the stream.  This releases any resources from the object.
     */
    void close();

    /+ Commented out for now, need to investigate how sharing works
        /**
     * Begin a read
     */
    void begin();

    /**
     * End a read
     */
    void end(); +/
}

/**
 * simple output interface
 */
interface OutputStream : Seek
{
    /**
     * Write a chunk of data to the output stream
     *
     * returns the number of bytes written on success.
     *
     * If 0 is returned, then the stream cannot be written to.
     */
    size_t put(const(ubyte)[] data);
    /// ditto
    alias put write;

    /**
     * Close the stream.  This releases any resources from the object.
     */
    void close();
}

interface BufferedOutput : Seek
{
    /**
     * Write a chunk of data to the buffer, flushing if necessary.
     *
     * If the data cannot be successfully written, an error is thrown.
     */
    void put(const(ubyte)[] data);
    /// ditto
    alias put write;

    /+ commented out for now, need to investigate shared more
    /**
     * Begin a write.  This can be used to optimize writes to the stream, such
     * as avoiding flushing until an entire write is done, or to take a lock on
     * the stream.
     *
     * The implementation may do nothing for this function.
     */
    void begin() shared;

    /**
     * End a write.  This can be used to optimize writes to the stream, such
     * as avoiding auto-flushing until an entire write is done, or to take a
     * lock on the stream.
     *
     * The implementation may do nothing for this function.
     */
    void end() shared; +/

    /**
     * Flush the written data in the buffer into the underlying output stream.
     */
    void flush();

    /**
     * Close the stream.  This releases any resources from the object.
     */
    void close();
}

class File : InputStream, OutputStream
{
    // the file descriptor
    // NOTE: we do not close this on destruction because this low level class
    // does not know where fd came from.  A derived class may choose to close
    // the file on destruction.
    //
    // fd is set to -1 when the stream is closed
    protected int fd = -1;

    /**
     * Construct an input stream based on the file descriptor
     */
    this(int fd)
    {
        this.fd = fd;
    }

    /**
     * Open a file as a dstream.  the specification for mode is identical
     * to the linux man page for fopen
     */
    static File open(const char[] name, const char[] mode = "rb")
    {
        if(!mode.length)
            throw new Exception("error in mode specification");
        // first, parse the open mode
        char m = mode[0];
        switch(m)
        {
        case 'r': case 'a': case 'w':
            break;
        default:
            throw new Exception("error in mode specification");
        }
        bool rw = false;
        bool bflag = false;
        foreach(i, c; mode[1..$])
        {
            if(i > 1)
                throw new Exception("Error in mode specification");
            switch(c)
            {
            case '+':
                if(rw)
                    throw new Exception("Error in mode specification");
                rw = true;
                break;
            case 'b':
                // valid, but does nothing
                if(bflag)
                    throw new Exception("Error in mode specification");
                bflag = true;
                break;
            default:
                throw new Exception("Error in mode specification");
            }
        }

        // create the flags
        int flags = rw ? O_RDWR : (m == 'r' ? O_RDONLY : O_WRONLY | O_CREAT);
        if(!rw && m == 'w')
            flags |= O_TRUNC;
        auto fd = .open(toStringz(name), flags, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH);
        if(fd < 0)
            throw new Exception("Error opening file, check errno");

        // wrap the file in a D stream
        auto result = new File(fd);

        // perform a seek if necessary
        if(m == 'a')
        {
            result.seek(0, Anchor.End);
        }

        return result;
    }

    long seek(long delta, Anchor whence=Anchor.Begin)
    {
        auto retval = lseek64(fd, delta, cast(int)whence);
        if(retval == -1)
        {
            // TODO: probably need an I/O exception
            throw new Exception("seek failed, check errno");
        }
        return retval;
    }

    @property bool seekable() const
    {
        // by default, we return true, because we cannot determine if a generic
        // file descriptor can be seeked.
        return true;
    }

    size_t read(ubyte[] data)
    {
        auto result = .read(fd, data.ptr, data.length);
        if(result < 0)
        {
            // TODO: need an I/O exception
            throw new Exception("read failed, check errno");
        }
        return cast(size_t)result;
    }

    size_t put(const(ubyte)[] data)
    {
        auto result = core.sys.posix.unistd.write(fd, data.ptr, data.length);
        if(result < 0)
        {
            throw new Exception("write failed, check errno");
        }
        return cast(size_t)result;
    }

    /**
     * Close this input stream.  Once it is closed, you can no longer use the
     * stream.
     */
    void close()
    {
        if(fd != -1)
            .close(fd);
        fd = -1;
    }

    /**
     * Destructor.  This is used as a safety net, in case the stream isn't
     * closed before being destroyed in the GC.
     */
    ~this()
    {
        close();
    }

    @property int handle()
    {
        return fd;
    }
}

/**
 * The D buffered input stream wraps a source InputStream with a buffering
 * system implemented in D.  Contrast this with the CStream which
 * uses C's FILE* abstraction.
 */
class DBufferedInput : BufferedInput
{
    protected
    {
        // the source stream
        InputStream input;

        // the buffered data
        ubyte[] buffer;

        // the number of bytes to add when the buffer need to be extended.
        size_t growSize;

        // the minimum read size for reading from the OS.  Attempting to read
        // more than this will avoid using the buffer if possible.
        size_t minReadSize;

        // the current position
        uint readpos = 0;

        // the position just beyond the last valid data.  This is like the end
        // of the valid data.
        uint valid = 0;
    }

    /**
     * Constructor.  Wraps an input stream.
     */
    this(InputStream input, uint defGrowSize = PAGE * 10, size_t minReadSize = PAGE)
    {
        this.minReadSize = minReadSize;
        this.input = input;
        // make sure the default grow size is at least the minimum read size.
        if(defGrowSize < minReadSize)
            defGrowSize = minReadSize;
        this.buffer = new ubyte[this.growSize = defGrowSize];

        // ensure we aren't wasting any space.
        this.buffer.length = this.buffer.capacity;
    }

    final size_t read(ubyte[] data)
    {
        size_t result = 0;
        // determine if there is any data in the buffer.
        if(data.length)
        {
            if(readpos < valid)
            {
                size_t nread = readpos + data.length;
                if(nread > valid)
                    nread = valid;
                result = nread - readpos;
                data[0..result] = buffer[readpos..nread];
                readpos = nread;
                data = data[result..$];
            }
            // at this point, either there is no data left in the buffer, or we
            // have filled up data.
            if(data.length)
            {
                // still haven't filled it up.  Try at least one read from the
                // input stream.
                if(data.length >= minReadSize)
                {
                    // data length is long enough to read into it directly.
                    return result + input.read(data);
                }
                // else, fill the buffer.  Even though we will be copying data,
                // it's probably more efficient than reading small chunks
                // from the stream.
                auto nread = input.read(buffer);
                if(nread > 0)
                {
                    readpos = data.length > nread ? nread : data.length;
                    valid = nread;
                    data[0..readpos] = buffer[0..readpos];
                    result += readpos;
                }
            }
        }
        return result;
    }
    
    alias BufferedInput.readln readln;
    final const(ubyte)[] readln(const(ubyte)[] lineterm)
    {
        immutable lastbyte = lineterm[$-1];
        size_t _checkDelim1(const(ubyte)[] data, size_t start)
        {
            auto ptr = data.ptr + start;
            auto end = data.ptr + data.length;
            for(;ptr < end; ++ptr)
            {
                if(*ptr == lastbyte)
                    break;
            }
            return ptr == end ? ~0 : ptr - data.ptr + 1;
        }

        size_t _checkDelimN(const(ubyte)[] data, size_t start)
        {
            // TODO; can try optimizing this
            auto ptr = data.ptr + start + lineterm.length - 1;
            auto end = data.ptr + data.length;
            auto ltend = lineterm.ptr + lineterm.length - 1;
            for(;ptr < end; ++ptr)
            {
                if(*ptr == lastbyte)
                {
                    // triggers a check
                    auto ptr2 = ptr - lineterm.length + 1;
                    auto ltptr = lineterm.ptr;
                    for(; ltptr < ltend; ++ltptr, ++ptr2)
                        if(*ltptr != *ptr2)
                            break;
                    if(ltptr == ltend)
                        break;
                }
            }
            return ptr >= end ? ~0 : ptr - data.ptr + 1;
        }

        return lineterm.length == 1 ? readUntil(&_checkDelim1) : readUntil(&_checkDelimN);
    }

    /**
     * Read data until a condition is satisfied.
     *
     * Buffers data from the input stream until the delegate returns other than
     * ~0.  The delegate is passed the data read so far, and the start of the
     * data just read.  The deleate should return ~0 if the condition is not
     * satisfied, or the number of bytes that should be returned otherwise.
     *
     * Any data that satisfies the condition will be considered consumed from
     * the stream.
     *
     * params: process = A delegate to determine satisfaction of a condition
     * per the terms above.
     *
     * returns: the data identified by the delegate that satisfies the
     * condition.  Note that this data may be owned by the buffer and so
     * shouldn't be written to or stored for later use without duping.
     */
    const(ubyte)[] readUntil(scope size_t delegate(const(ubyte)[] data, size_t start) process)
    {
        // read data from the buffer/stream until the condition is met,
        // expanding the buffer as necessary
        auto d = buffer[readpos..valid];
        auto status = d.length ? process(d, 0) : ~0;

        // TODO: this simple version always moves data to the front
        // of the buffer if the buffer is filled, but a smarter version
        // could probably only move data when it's most efficient.  We
        // probably need GC support for that.
        if(status == ~0 && readpos > 0)
        {
            memmove(buffer.ptr, buffer.ptr + readpos, valid -= readpos);
            readpos = 0;
        }

        while(status == ~0)
        {
            auto avail = buffer.length - valid;
            if(avail < minReadSize)
            {
                buffer.length += growSize;

                // always use up as much space as possible.
                buffer.length = buffer.capacity;
            }

            auto nread = input.read(buffer[valid..$]);
            if(!nread)
            {
                // no more data available from the stream, process the EOF
                process(buffer[0..valid], valid);
                status = valid;
            }
            else
            {
                status = process(buffer[0..valid + nread], valid);
                valid += nread;
            }
        }

        // adjust the read buffer, and return the data.

        auto ep = readpos + status;
        d = buffer[readpos..readpos + status];
        if(ep == valid)
            valid = readpos = 0;
        else
            readpos = ep;
        return d;
    }

    /**
     * Read data into a given buffer until a condition is satisfied.
     *
     * This performs just like readUntil, except the data is written to the
     * given array.  Since the caller owns this array, it controls the lifetime
     * of the array.  Any excess data will be pushed back into the stream's
     * buffer.
     *
     * Note that more data may be written into the buffer than satisfies the
     * condition, but that data is not considered to be consumed from the
     * stream.
     *
     * params:
     * process = A delegate to determine satisfaction of a condition
     * per the terms above.
     * arr = The array that will be written to.  The array may be extended as
     * necessary.
     *
     * returns: The number of bytes in arr that are valid.
     */
    size_t appendUntil(scope size_t delegate(const(ubyte)[] data, size_t start) process,
                                ref ubyte[] arr)
    {
        // read data from the buffer/stream until the condition is met,
        // expanding the input array as necessary
        auto d = buffer[readpos..valid];
        size_t status = void;
        size_t avalid = 0;
        if(d.length)
        {
            // see if the buffer satisfies
            status = d.length ? process(d, 0) : ~0;
            if(status != ~0)
            {
                // the buffer was enough, copy it to the array
                if(arr.length < status)
                {
                    arr.length = status;
                }
                arr[0..status] = d[0..status];
                readpos += status;
                return status;
            }
            // no satisfaction, copy the current buffer data to the array, and
            // continue.
            if(arr.length < d.length)
            {
                arr.length = d.length + growSize;
                // make sure we expand to capacity
                arr.length = arr.capacity;
            }
            arr[0..d.length] = d[];
            avalid = d.length;
            // clear out the buffer.
            readpos = valid = 0;
        }


        while(status == ~0)
        {
            if(arr.length - avalid < minReadSize)
            {
                arr.length += growSize;
                // always use up as much space as possible.
                arr.length = arr.capacity;
            }

            auto nread = input.read(arr[avalid..$]);
            if(!nread)
            {
                // no more data available from the stream, process the EOF
                process(arr[0..avalid], avalid);
                status = avalid;
            }
            else
            {
                status = process(arr[0..avalid + nread], avalid);
                avalid += nread;
            }
        }

        assert(status <= avalid);
        // data has been processed, put back any data that wasn't processed.
        auto putback = avalid - status;
        if(buffer.length < putback)
        {
            buffer.length = putback;
        }
        buffer[0..putback] = arr[status..avalid];
        valid = putback;
        readpos = 0;
        return status;
    }

    override ulong seek(long delta, Anchor whence=Anchor.Begin)
    {
        switch(whence)
        {
        case Anchor.Current:
            // see if we can see within the buffer
            {
                auto target = readpos + delta;
                if(target < 0 || target > valid)
                {
                    delta -= (valid - readpos);
                    goto case Anchor.Begin;
                }

                // can seek within our buffer
                readpos = cast(size_t)target;

                if(input.seekable())
                    return input.tell() - (valid - readpos);
                return ~0;
            }

        case Anchor.Begin, Anchor.End:
            // reset the buffer and seek the underlying stream
            readpos = valid = 0;
            return input.seek(delta, whence);

        default:
            // TODO: throw an exception
            return ~0;
        }
    }

    override @property bool seekable() const
    {
        return input.seekable();
    }

    @property size_t bufsize()
    {
        return buffer.length;
    }

    @property size_t readable()
    {
        return valid - readpos;
    }

    override void close()
    {
        input.close();
        readpos = valid = 0;
    }

    /*override void begin() shared
    {
        // no specialized code needed.
    }

    override void end() shared
    {
        // no specialized code needed.
    }*/

    @property ByChunk byChunk(size_t chunkSize = 0)
    {
        if(chunkSize == 0)
            // default to a reasonable chunk size
            chunkSize = buffer.length / 4;
        return ByChunk(this, chunkSize);
    }
}

class DBufferedOutput : BufferedOutput
{
    protected
    {
        // the source stream
        OutputStream output;

        // the buffered data
        ubyte[] buffer;

        // the current position in the buffer for writing.  Everything
        // before this position is valid data to be written to the stream.
        uint writepos = 0;

        // function to check how much data should be flushed.
        ptrdiff_t delegate(const(ubyte)[] data) _flushCheck;

        // function to encode data for writing.  This is called prior to
        // writing the data to the underlying stream.  When this is set, extra
        // copies of the data may be made.
        void delegate(ubyte[] data) _encode;

        // if this is set, _flushCheck should not be called when checking for
        // automatic flushing.
        bool _noflushcheck = false;
        size_t _startofwrite = 0;
    }

    /**
     * Constructor.  Wraps an output stream.
     */
    this(OutputStream output, uint bufsize = PAGE * 10)
    {
        this.output = output;
        this.buffer = new ubyte[bufsize];

        // ensure we aren't wasting any space.
        this.buffer.length = this.buffer.capacity;
    }

    /+ commented out for now, not sure how shared classes are going to work for I/O
    final void begin()
    in
    {
        assert(!_noflushcheck);
    }
    body
    {
        // disable flush checking, this is going to be a "single" write.
        _noflushcheck = true;

        // _startofwrite stores the write position we had when beginning, so we
        // can properly check the "added" data.
        _startofwrite = writepos;
    }

    final void end()
    in
    {
        assert(_noflushcheck);
    }
    body
    {
        // re-enable flush checking, A single write is completed.
        _noflushcheck = false;

        // OK, so all flush checking was delayed, need to do a flush check.
        if(writepos < _startofwrite)
            throw new Exception("here");
        if(_flushCheck && writepos - _startofwrite > 0)
        {
            auto fcheck = _flushCheck(buffer[_startofwrite..writepos]);
            if(fcheck >= 0)
            {
                // need to flush some data
                auto endpos = _startofwrite + fcheck;
                if(_encode)
                    _encode(buffer[0..endpos]);

                ensureWrite(buffer[0..endpos], endpos);

                // now, we need to move the data to the front of the buffer
                // this is the only place we have to do this.
                if(writepos != endpos)
                    memmove(buffer.ptr, buffer.ptr + endpos, writepos - endpos);
                writepos -= endpos;
            }
        }
        _startofwrite = 0;
    } +/

    final void put(const(ubyte)[] data)
    {
        if(!data.length)
            return;
        // determine if any data should be flushed before writing.
        auto fcheck = !_noflushcheck && _flushCheck ? _flushCheck(data) : -1;
        assert(fcheck <= cast(ptrdiff_t)data.length);
        // minwrite is the number of bytes that must be written to the
        // stream.
        size_t minwrite = (fcheck == -1) ? 0 : fcheck + writepos;
        if(data.length + writepos - minwrite > buffer.length)
        {
            // minwrite is too small, the leftover data wouldn't fit
            // into the buffer
            minwrite = data.length + writepos - buffer.length;
            // want to at least write a full buffer
            if(minwrite < buffer.length)
                minwrite = buffer.length;
            fcheck = -1;
        }
        // maxwrite is the number of bytes to try writing.  If fcheck
        // did not return -1 then we need to respect its wishes, otherwise,
        // we should write as much as possible in one go.
        size_t maxwrite = (fcheck == -1) ? data.length + writepos : fcheck;
        if(minwrite > 0)
        {
            // need to write some data to the actual stream. But we want to
            // minimize the calls to output.put.
            if(_encode)
            {
                // simple case, everything must be buffered and encoded before
                // its written, so just do that in a loop.  This handles all
                // possible values of minwrite and whether there is data in the
                // buffer already.
                if(writepos)
                {
                    // already data in the buffer, this is a special case, we
                    // can optimize the rest in the loop.
                    auto ntoCopy = minwrite - writepos;
                    if(ntoCopy + writepos > buffer.length)
                        ntoCopy = buffer.length - writepos;
                    auto totalbytes = writepos + ntoCopy;
                    buffer[writepos..totalbytes] = data[0..ntoCopy];
                    data = data[ntoCopy..$];
                    _encode(buffer[0..totalbytes]);
                    ensureWrite(buffer[0..totalbytes], totalbytes);
                    writepos = _startofwrite = 0;
                    minwrite -= totalbytes;
                }
                while(minwrite > 0)
                {
                    assert(writepos == 0); // sanity check.
                    auto ntoCopy = minwrite > buffer.length ? buffer.length : minwrite;
                    auto dest = buffer[0..ntoCopy];
                    dest[] = data[0..ntoCopy];
                    data = data[ntoCopy..$];
                    _encode(dest);
                    ensureWrite(dest, dest.length);
                    minwrite -= ntoCopy;
                }

                // copy whatever is left over.
                if(data.length)
                {
                    buffer[0..data.length] = data[];
                    writepos = data.length;
                }
            }
            else if(writepos && minwrite <= buffer.length)
            {
                // valid data in the buffer.  Easiest thing to do is to
                // write the minimum data to the buffer, ensure it gets
                // written, then populate the buffer with the leftovers.
                auto nCopy = minwrite - writepos;
                buffer[writepos..minwrite] = data[0..nCopy];
                data = data[nCopy..$];

                ensureWrite(buffer[0..minwrite], minwrite);
                // copy leftovers to the buffer
                writepos = data.length;
                // reset _startofwrite in case we are tracking a single write.
                _startofwrite = 0;
                buffer[0..writepos] = data[];
            }
            else
            {
                // either the buffer contains no data, or the minimum written
                // data needs to be written in more than one write statement.
                // first, write any data from the buffer
                if(writepos)
                {
                    // write out the data in the buffer
                    ensureWrite(buffer[0..writepos], writepos);
                    minwrite -= writepos;
                    maxwrite -= writepos;
                    writepos = 0;
                    // reset _startofwrite in case we are tracking a single
                    // write.
                }
                // now, write data directly from the passed in slice.
                auto nwritten = ensureWrite(data[0..maxwrite], minwrite);
                _startofwrite = 0;
                if(nwritten != data.length)
                {
                    // copy the leftovers to the buffer
                    writepos = data.length - nwritten;
                    buffer[0..writepos] = data[nwritten..$];
                }
            }
        }
        else
        {
            // no data needs to be written to the stream, just buffer
            // everything.
            buffer[writepos..writepos + data.length] = data[];
            writepos += data.length;
        }
    }

    override ulong seek(long delta, Anchor whence=Anchor.Begin)
    {
        switch(whence)
        {
        case Anchor.Current:
            if(delta == 0)
                // special case for tell
                return output.tell() + writepos;
            
            // else go to the normal case of simply flushing and seeking.
            // Otherwise, the data we have written to the buffer could be
            // lost.
            goto case Anchor.Begin;

        case Anchor.Begin, Anchor.End:
            // flush the buffer and seek the underlying stream
            flush();
            return output.seek(delta, whence);

        default:
            // TODO: throw an exception
            return ~0;
        }
    }

    override @property bool seekable() const
    {
        return output.seekable();
    }

    @property size_t bufsize()
    {
        return buffer.length;
    }

    @property size_t readyToWrite()
    {
        return writepos;
    }

    @property size_t writeable()
    {
        return buffer.length - writepos;
    }

    /**
     * Close the stream.  Note, if you do not call this function, there is no
     * guarantee the data will be flushed to the stream.  This is due to the
     * non-deterministic behavior of the GC.
     */
    override void close()
    {
        flush();
        output.close();
    }

    override void flush()
    {
        if(writepos)
        {
            if(_encode)
                _encode(buffer[0..writepos]);
            ensureWrite(buffer[0..writepos], writepos);
            writepos = 0;
        }
    }

    /**
     * Set the buffer flush checker.  This delegate determines whether the
     * buffer should be flushed immediately after a write.  If this routine is
     * not set, the default is to flush after the buffer is full.
     *
     * the buffer check function is passed data that will be written to the
     * buffer/stream.  If no trigger to flush is found, the delegate should
     * return -1.  If a trigger is found, it should return the number of bytes
     * from the data that should be flushed.  If there is more than one
     * trigger, return the *largest* such value.
     *
     * This function will be overridden if the total data exceeds the buffer
     * size.
     */
    @property void flushCheck(ptrdiff_t delegate(const(ubyte)[] newData) dg)
    {
        _flushCheck = dg;
    }

    /**
     * Get the buffer flush checker.  This delegate determines whether the
     * buffer should be flushed immediately after a write.  If this routine is
     * not set, the default is to flush after the buffer is full.
     */
    ptrdiff_t delegate(const(ubyte)[] newData) flushCheck() @property
    {
        return _flushCheck;
    }

    /**
     * The encoder is responsible for transforming data into the correct
     * encoding when writing to a stream.  For instance, a UTF-16 file with
     * byte order different than the native machine will likely need to be
     * byte-swapped before being written.
     *
     * If this is set to non-null, extra copying may occur as a writable buffer
     * is needed to encode the stream.
     */ 
    @property void encoder(void delegate(ubyte[] data) dg)
    {
        _encode = dg;
    }

    /**
     * Get the encoder function.
     */
    void delegate(ubyte[] data) encoder() @property
    {
        return _encode;
    }

    private size_t ensureWrite(const(ubyte)[] data, ptrdiff_t minsize)
    in
    {
        assert(minsize >= 0);
        assert(minsize <= data.length);
    }
    body
    {
        // write in a loop until the minimum data is written.
        size_t result;
        while(minsize > 0)
        {
            auto nwritten = output.put(data);
            if(!nwritten) // eof
                break;
            result += nwritten;
            minsize -= nwritten;
            data = data[nwritten..$];
        }
        return result;
    }
}

struct ByChunk
{
    private DBufferedInput _input;
    private size_t _size;
    private const(ubyte)[] _curchunk;

    this(InputStream input, size_t size)
    {
        this(new DBufferedInput(input), size);
    }

    this(DBufferedInput dbi, size_t size)
    in
    {
        assert(size, "size cannot be greater than zero");
    }
    body
    {
        this._input = dbi;
        this._size = size;
        popFront();
    }

    void popFront()
    {
        _curchunk = _input.readUntil(&stopCondition);
    }

    @property const(ubyte)[] front()
    {
        return _curchunk;
    }

    @property bool empty() const
    {
        return _curchunk.length == 0;
    }

    private size_t stopCondition(const(ubyte)[] data, size_t start)
    {
        return data.length >= _size ? _size : ~0;
    }

    /**
     * Close the input stream forcibly
     */
    void close()
    {
        _input.close();
    }
}

class CStream : BufferedInput, BufferedOutput
{
    private
    {
        FILE *source;
        char *_buf; // C malloc'd buffer used to support getDelim
        size_t _bufsize; // size of buffer
        ubyte _charwidth; // width of the stream (orientation)
        bool _locked; // whether the stream is locked or not.
    }

    enum GROW_SIZE = 1024; // optimized for FILE buffer sizes

    /**
     * Note, source must ALWAYS be a virgin stream.  That is, there should not
     * have been an i/o operation on the stream, or the buffering will not work
     * properly.
     */
    this(FILE *source)
    {
        this.source = source;
        this._charwidth = .fwide(source, 0) < 0 ? 1 : 2;
    }

    // comment out for now, not sure how this will work.
    /+void begin()
    {
        FLOCK(source);
    }

    void end()
    {
        FUNLOCK(source);
    }+/

    override ulong seek(long delta, Anchor whence=Anchor.Begin)
    {
        static if(is(typeof(&fseeko64)))
        {
            if(whence != Anchor.Current || delta != 0)
            {
                // have 64-bit fseek
                if(fseeko64(source, delta, whence) != 0)
                {
                    throw new Exception("Error seeking");
                }
            }
            return ftello64(source);
        }
        else
        {
            if(whence != Anchor.Current || delta != 0)
            {
                // don't have 64-bit seek.  Ensure seek range fits in an int
                if(delta < int.min || delta > int.max)
                    throw new Exception("64-bit seek not supported");
                if(fseek(source, cast(int)delta, whence) != 0)
                {
                    throw new Exception("Error seeking");
                }
            }
            return cast(long)ftell(source);
        }
    }

    override @property bool seekable() const
    {
        // can always try to seek a FILE, no way to tell from the FILE.
        return true;
    }

    override size_t read(ubyte[] data)
    {
        if(_charwidth == 1)
        {
            size_t result = .fread(data.ptr, ubyte.sizeof, data.length, source);
            if(result < data.length)
            {
                // could be error or eof, check error
                if(ferror(source))
                    throw new Exception("Error reading");
            }
            return result;
        }
        else
        {
            // wide character mode, need to use fgetwc
        }
    }

    const(ubyte)[] readln(const(ubyte)[] lineterm)
    {
        // TODO: make sure this is correct for line termination...
        assert(lineterm.length <= 4);
        int ltarg = 0;
        foreach(ub; lineterm)
            ltarg = (ltarg << 8) | cast(uint)ub;
            
        auto result = .getdelim(&_buf, &_bufsize, ltarg, source);
        if(result < 0)
            // Throw instead?
            return null;
        return (cast(ubyte *)_buf)[0..result];
    }


    /**
     * Get the underlying FILE*.  Use this for optimizing when possible.
     */
    @property FILE *cFile()
    {
        return source;
    }

    override void close()
    {
        if(source)
           fclose(source);
        source = null;
        if(_buf)
            .free(_buf);
        _buf = null;
        _bufsize = 0;
    }

    // BufferedOutput interface
    void put(const(ubyte)[] data)
    {
        if(_charwidth == 1)
        {
            // optimized, just write using fwrite.
            auto result = fwrite(data.ptr, ubyte.sizeof, data.length, source);
            if(result < data.length)
            {
                derr.writeln("Error writing data: ", result, " ", data.length);
                throw new Exception("Error writing data");
            }
        }
        else
        {
            // in wide mode, we must use FPUTWC
        }
    }

    void flush()
    {
        fflush(source);
    }

    // just in case close isn't called before the GC gets to this object.
    ~this()
    {
        close();
    }

    static CStream open(const char[] name, const char[] mode = "rb")
    {
        return new CStream(.fopen(toStringz(name), toStringz(mode)));
    }
}

// formatted input stream
struct TextInput
{
    private BufferedInput input;

    void construct(InputStream ins)
    {
        construct(new DBufferedInput(ins));
    }

    void construct(FILE *fp)
    {
        construct(new CStream(fp));
    }

    void construct(BufferedInput input)
    {
        this.input = input;
    }
}

/*struct ByLine(Char, Terminator)
{
    BufferedInput input;
    Char[] line;
    Terminator terminator;
    KeepTerminator keepTerminator;
}*/

/**
 * The width of the text stream
 */
enum StreamWidth : ubyte
{
    /// Determine width on first access (valid only for CStream streams)
    AUTO = 0,

    /// 8 bit width
    UTF8 = 1,

    /// 16 bit width
    UTF16 = 2,

    /// 32 bit width
    UTF32 = 4
}

/**
 * The byte order of a text stream
 */
enum ByteOrder
{
    /// Use native byte order (no encoding necessary).  This is the only
    /// possibility for CStream streams.
    Native,

    /// Use Little Endian byte order.  Has no effect on 8-bit streams.
    Little,

    /// Use Big Endian byte order.  Has no effect on 8-bit streams.
    Big
}

private void __swapBytes(ubyte[] data, ubyte charwidth)
{
    // depending on the char width, do byte swapping on the data stream.
    assert(data.length % charwidth == 0);
    switch(charwidth)
    {
    case wchar.sizeof:
        // swap every 2 bytes
        // TODO: optimize this
        foreach(ref t; cast(ushort[])data)
        {
            t = ((t << 8) & 0xff00) |
                ((t >> 8) & 0x00ff);
        }
        break;
    case dchar.sizeof:
        // swap every 4 bytes
        // TODO: optimize this
        foreach(ref t; cast(uint[])data)
        {
            t = ((t << 24) & 0xff000000) |
                ((t << 8)  & 0x00ff0000) |
                ((t >> 8)  & 0x0000ff00) |
                ((t >> 24) & 0x000000ff);
        }
        break;
    default:
        assert(0, "invalid charwidth");
    }
}

// formatted output stream
//
// Note, this should never be on the stack, it should only ever be allocated on
// the heap or in the global segment.
struct TextOutput
{
    // the actual buffered output stream.
    private BufferedOutput _output;

    /**
     * Fetch the buffered output stream that backs this text outputter
     */
    @property BufferedOutput output()
    {
        return _output;
    }

    // this is settable at runtime because the interface to a text stream is
    // independent of the character width being sent to it.  Otherwise, it
    // would not be possible to say, for example, change the output width to
    // wchar for stdou.
    private ubyte _charwidth;

    private void encode(ubyte[] data)
    {
        __swapBytes(data, _charwidth);
    }

    private ptrdiff_t flushLineCheckT(T)(const(T)[] data)
    {
        for(const(T)* i = data.ptr + data.length - 1; i >= data.ptr; --i)
        {
            if(*i == cast(T)'\n')
                return (i - data.ptr + 1) * T.sizeof;
        }
        return -1;
    }

    private ptrdiff_t flushLineCheck(const(ubyte)[] data)
    {
        switch(_charwidth)
        {
        case 1:
            return flushLineCheckT(cast(const(char)[])data);
        case 2:
            return flushLineCheckT(cast(const(wchar)[])data);
        case 4:
            return flushLineCheckT(cast(const(dchar)[])data);
        default:
            assert(0, "invalid width");
        }
    }

    void construct(OutputStream outs, StreamWidth width = StreamWidth.UTF8, ByteOrder bo = ByteOrder.Native)
    in
    {
        // don't support auto width.
        assert(width == StreamWidth.UTF8 || width == StreamWidth.UTF16 ||
               width == StreamWidth.UTF32);
        assert(bo == ByteOrder.Native || bo == ByteOrder.Little ||
               bo == ByteOrder.Big);
    }
    body
    {
        auto dbo = new DBufferedOutput(outs);
        if(width != StreamWidth.UTF8)
        {
            version(LittleEndian)
            {
                if(bo == ByteOrder.Big)
                    dbo.encoder = &encode;
            }
            else
            {
                if(bo == ByteOrder.Little)
                    dbo.encoder = &encode;
            }
        }

        if(auto f = cast(File)outs)
        {
            // this is a device stream, check to see if it's a terminal
            version(Posix)
            {
                if(isatty(f.handle))
                {
                    // by default, do a flush check based on a newline
                    dbo.flushCheck = &flushLineCheck;
                }
            }
            else
                static assert(0, "Unsupported OS");
        }
        construct(dbo, width);
    }

    void construct(FILE *outs, StreamWidth width = StreamWidth.AUTO)
    in
    {
        // don't support 32-bit width for C streams
        assert(width == StreamWidth.UTF8 || width == StreamWidth.UTF16 ||
               width == StreamWidth.AUTO);
    }
    body
    {
        int mode = void;
        switch(width)
        {
        case StreamWidth.AUTO:
            mode = 0;
            break;

        case StreamWidth.UTF8:
            mode = -1;
            break;

        case StreamWidth.UTF16:
            mode = 1;
            break;

        default:
            assert(0, "Invalid width");
        }

        if(.fwide(outs, mode) < 0)
            width = StreamWidth.UTF8;
        else
            width = StreamWidth.UTF16;
        construct(new CStream(outs), width);
    }

    void construct(BufferedOutput outs, StreamWidth width = StreamWidth.UTF8)
    in
    {
        assert(width == StreamWidth.UTF8 || width == StreamWidth.UTF16 ||
               width == StreamWidth.UTF32 || width == StreamWidth.AUTO);
    }
    body
    {
        this._output = outs;
        this._charwidth = width;
    }

    void write(S...)(S args)
    {
        switch(_charwidth)
        {
        case 1:
            priv_write!(char)(args);
            break;
        case 2:
            priv_write!(wchar)(args);
            break;
        case 4:
            priv_write!(dchar)(args);
            break;
        default:
            assert(0);
        }
    }

    void writeln(S...)(S args)
    {
        switch(_charwidth)
        {
        case 1:
            priv_write!(char)(args, '\n');
            break;
        case 2:
            priv_write!(wchar)(args, '\n');
            break;
        case 4:
            priv_write!(dchar)(args, '\n');
            break;
        default:
            assert(0);
        }
    }

    private void priv_write(C, S...)(S args)
    {
        //_output.begin();
        auto w = OutputRange!C(_output);

        foreach(arg; args)
        {
            alias typeof(arg) A;
            static if (isSomeString!A)
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
        //_output.end();
    }

    private enum errorMessage =
        "You must pass a formatting string as the first"
        " argument to writef or writefln. If no formatting is needed,"
        " you may want to use write or writeln.";

    void writef(S...)(S args)
    {
        static assert(S.length > 0, errorMessage);
        static assert(isSomeString!(S[0]), errorMessage);
        switch(_charwidth)
        {
        case 1:
            priv_writef!(char, false)(args);
            break;
        case 2:
            priv_writef!(wchar, false)(args);
            break;
        case 4:
            priv_writef!(dchar, false)(args);
            break;
        default:
            assert(0);
        }
    }

    void writefln(S...)(S args)
    {
        static assert(S.length > 0, errorMessage);
        static assert(isSomeString!(S[0]), errorMessage);
        switch(_charwidth)
        {
        case 1:
            priv_writef!(char, true)(args);
            break;
        case 2:
            priv_writef!(wchar, true)(args);
            break;
        case 4:
            priv_writef!(dchar, true)(args);
            break;
        default:
            assert(0);
        }
    }

    private void priv_writef(C, bool doNewline, S...)(S args)
    {
        static assert(S.length > 0, errorMessage);
        static assert(isSomeString!(S[0]), errorMessage);
        //_output.begin();
        auto w = OutputRange!C(_output);
        std.format.formattedWrite(w, args);
        static if(doNewline)
        {
            w.put('\n');
        }
        //_output.end();
    }


    private struct OutputRange(CT)
    {
        BufferedOutput output;

        this(BufferedOutput output)
        {
            this.output = output;
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
                output.put(cast(const(ubyte)[]) writeme);
            }
            else
            {
                // convert to dchars, put each one out there.
                foreach(dchar dc; writeme)
                {
                    put(dc);
                }
            }
        }

        void put(A)(A c) if(is(A : const(dchar)))
        {
            static if(A.sizeof == CT.sizeof)
            {
                // output the data directly to the output stream
                output.put(cast(ubyte[])((&c)[0..1]));
            }
            else
            {
                static if(CT.sizeof == 1)
                {
                    // convert the character to utf8
                    char[4] buf = void;
                    output.put(cast(ubyte[])std.utf.toUTF8(buf, c));
                }
                else static if(CT.sizeof == 2)
                {
                    // convert the character to utf16
                    wchar[2] buf = void;
                    output.put(cast(ubyte[])std.utf.toUTF16(buf, c));
                }
                else static if(CT.sizeof == 4)
                {
                    // converting to utf32, just write directly
                    dchar dc = c;
                    assert(isValidDchar(dc));
                    output.put(cast(ubyte[])(&dc)[0..1]);
                }
                else
                    static assert(0, "invalid types used for output stream, " ~ CT.stringof ~ ", " ~ C.stringof);
            }
        }
    }

    void flush()
    {
        _output.flush();
    }

    void close()
    {
        _output.close();
    }
}

auto openFile(string mode = "r")(string fname)
{
    static if(mode == "r")
        return new DBufferedInput(File.open(fname, mode));
    else
        static assert(0, "mode not supported for openFile: " ~ mode);
}

__gshared {

    File stdin;
    File stdout;
    File stderr;

    TextInput din;
    TextOutput dout;
    TextOutput derr;
}

shared static this()
{
    version(linux)
    {
        stdin = new File(0);
        stdout = new File(1);
        stderr = new File(2);
    }
    else
        static assert(0, "Unsupported OS");

    // set up the shared buffered streams
    din.construct(stdin);
    dout.construct(stdout);
    derr.construct(stderr);
}

shared static ~this()
{
    // we could possibly close, but since these are the main output streams,
    // we'll just flush the buffers.
    dout.flush();
    derr.flush();
}

void useCStdio()
{
    din.construct(core.stdc.stdio.stdin);
    dout.construct(core.stdc.stdio.stdout);
    derr.construct(core.stdc.stdio.stderr);
}

/***********************************
For each argument $(D arg) in $(D args), format the argument (as per
$(LINK2 std_conv.html, to!(string)(arg))) and write the resulting
string to $(D args[0]). A call without any arguments will fail to
compile.

Throws: In case of an I/O error, throws an $(D StdioException).
 */
void write(T...)(T args) if (!is(T[0] : File))
{
    dout.write(args);
}

unittest
{
    //printf("Entering test at line %d\n", __LINE__);
    scope(failure) printf("Failed test at line %d\n", __LINE__);
    void[] buf;
    write(buf);
    // test write
    string file = "dmd-build-test.deleteme.txt";
    auto f = File(file, "w");
//    scope(exit) { std.file.remove(file); }
     f.write("Hello, ",  "world number ", 42, "!");
     f.close;
     assert(cast(char[]) std.file.read(file) == "Hello, world number 42!");
    // // test write on stdout
    //auto saveStdout = stdout;
    //scope(exit) stdout = saveStdout;
    //stdout.open(file, "w");
    Object obj;
    //write("Hello, ",  "world number ", 42, "! ", obj);
    //stdout.close;
    // auto result = cast(char[]) std.file.read(file);
    // assert(result == "Hello, world number 42! null", result);
}

// Most general instance
void writeln(T...)(T args)
{
    dout.writeln(args);
}

unittest
{
        //printf("Entering test at line %d\n", __LINE__);
    scope(failure) printf("Failed test at line %d\n", __LINE__);
    // test writeln
    string file = "dmd-build-test.deleteme.txt";
    auto f = File(file, "w");
    scope(exit) { std.file.remove(file); }
    f.writeln("Hello, ",  "world number ", 42, "!");
    f.close;
    version (Windows)
        assert(cast(char[]) std.file.read(file) ==
                "Hello, world number 42!\r\n");
    else
        assert(cast(char[]) std.file.read(file) ==
                "Hello, world number 42!\n");
    // test writeln on stdout
    auto saveStdout = stdout;
    scope(exit) stdout = saveStdout;
    stdout.open(file, "w");
    writeln("Hello, ",  "world number ", 42, "!");
    stdout.close;
    version (Windows)
        assert(cast(char[]) std.file.read(file) ==
                "Hello, world number 42!\r\n");
    else
        assert(cast(char[]) std.file.read(file) ==
                "Hello, world number 42!\n");
}

/***********************************
 * If the first argument $(D args[0]) is a $(D FILE*), use
 * $(LINK2 std_format.html#format-string, the format specifier) in
 * $(D args[1]) to control the formatting of $(D
 * args[2..$]), and write the resulting string to $(D args[0]).
 * If $(D arg[0]) is not a $(D FILE*), the call is
 * equivalent to $(D writef(stdout, args)).
 *

IMPORTANT:

New behavior starting with D 2.006: unlike previous versions,
$(D writef) (and also $(D writefln)) only scans its first
string argument for format specifiers, but not subsequent string
arguments. This decision was made because the old behavior made it
unduly hard to simply print string variables that occasionally
embedded percent signs.

Also new starting with 2.006 is support for positional
parameters with
$(LINK2 http://opengroup.org/onlinepubs/009695399/functions/printf.html,
POSIX) syntax.

Example:

-------------------------
writef("Date: %2$s %1$s", "October", 5); // "Date: 5 October"
------------------------

The positional and non-positional styles can be mixed in the same
format string. (POSIX leaves this behavior undefined.) The internal
counter for non-positional parameters tracks the popFront parameter after
the largest positional parameter already used.

New starting with 2.008: raw format specifiers. Using the "%r"
specifier makes $(D writef) simply write the binary
representation of the argument. Use "%-r" to write numbers in little
endian format, "%+r" to write numbers in big endian format, and "%r"
to write numbers in platform-native format.

*/

void writef(T...)(T args)
{
    dout.writef(args);
}

unittest
{
    //printf("Entering test at line %d\n", __LINE__);
    scope(failure) printf("Failed test at line %d\n", __LINE__);
    // test writef
    string file = "dmd-build-test.deleteme.txt";
    auto f = File(file, "w");
    scope(exit) { std.file.remove(file); }
    f.writef("Hello, %s world number %s!", "nice", 42);
    f.close;
    assert(cast(char[]) std.file.read(file) ==  "Hello, nice world number 42!");
    // test write on stdout
    auto saveStdout = stdout;
    scope(exit) stdout = saveStdout;
    stdout.open(file, "w");
    writef("Hello, %s world number %s!", "nice", 42);
    stdout.close;
    assert(cast(char[]) std.file.read(file) == "Hello, nice world number 42!");
}

/***********************************
 * Equivalent to $(D writef(args, '\n')).
 */
void writefln(T...)(T args)
{
    dout.writefln(args);
}

unittest
{
        //printf("Entering test at line %d\n", __LINE__);
    scope(failure) printf("Failed test at line %d\n", __LINE__);
    // test writefln
    string file = "dmd-build-test.deleteme.txt";
    auto f = File(file, "w");
    scope(exit) { std.file.remove(file); }
    f.writefln("Hello, %s world number %s!", "nice", 42);
    f.close;
    version (Windows)
        assert(cast(char[]) std.file.read(file) ==
                "Hello, nice world number 42!\r\n");
    else
        assert(cast(char[]) std.file.read(file) ==
                "Hello, nice world number 42!\n",
                cast(char[]) std.file.read(file));
    // test write on stdout
    // auto saveStdout = stdout;
    // scope(exit) stdout = saveStdout;
    // stdout.open(file, "w");
    // assert(stdout.isOpen);
    // writefln("Hello, %s world number %s!", "nice", 42);
    // foreach (F ; TypeTuple!(ifloat, idouble, ireal))
    // {
    //     F a = 5i;
    //     F b = a % 2;
    //     writeln(b);
    // }
    // stdout.close;
    // auto read = cast(char[]) std.file.read(file);
    // version (Windows)
    //     assert(read == "Hello, nice world number 42!\r\n1\r\n1\r\n1\r\n", read);
    // else
    //     assert(read == "Hello, nice world number 42!\n1\n1\n1\n", "["~read~"]");
}

