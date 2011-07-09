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
    core.stdc.string, core.stdc.wchar_, core.bitop;
import std.traits;
import std.range;
import std.utf;
import std.conv;
import std.typecons;

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
    private int fd = -1;

    // flag indicating the destructor should not close the stream.  Useful when
    // a File does not own the fd in question.
    private bool _closeOnDestroy;

    /**
     * Construct an input stream based on the file descriptor
     */
    this(int fd, bool closeOnDestroy = true)
    {
        this.fd = fd;
        this._closeOnDestroy = closeOnDestroy;
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
        if(_closeOnDestroy)
            close();
        else
            fd = -1;
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
class DInput : BufferedInput
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
        size_t readpos = 0;

        // the position just beyond the last valid data.  This is like the end
        // of the valid data.
        size_t valid = 0;

        // a decoder function.  When set, this decodes data coming in.  This is
        // useful for cases where for example byte-swapping must be done.  It
        // should return the number of bytes processed (for example, if you are
        // byte-swapping every 2 bytes, and data contains an odd number of
        // bytes, you cannot process the last byte.
        size_t delegate(ubyte[] data) _decode;

        // the number of bytes already decoded (always set to valid if _decode
        // is unset)
        size_t decoded = 0;
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
            // save this for later so we can decode the data.
            auto origdata = data;
            size_t origdata_decoded = decoded - readpos;
            if(decoded < valid)
            {
                // there's some leftover undecoded data in the buffer.  the
                // expectation is that this data is small in size, so it can be
                // moved to the front of the buffer efficiently.  We don't read
                // data into a buffer without trying to decode it.
                //
                if(origdata_decoded >= data.length)
                {
                    // already decoded data will satisfy the read request, just
                    // copy and move the read pointer.
                    data[] = buffer[readpos..readpos+data.length];
                    readpos += data.length;
                    // shortcut, no need to deal with decoding anything.
                    return data.length;
                }

                // else, there is at least some non-decoded data we have to
                // deal with.  If it makes sense to read directly into the data
                // buffer, then don't bother moving the data to the front of
                // the buffer, we'll read directly into the data.
                ptrdiff_t nleft = data.length - (valid - readpos);
                if(nleft >= minReadSize)
                {
                    // read directly into data.
                    result = valid - readpos;
                    data[0..result] = buffer[readpos..valid];
                    result += input.read(data[result..$]);
                    readpos = decoded = valid = 0; // reset buffer
                    // we will decode the data later.
                }
                else
                {
                    // too small to read into data directly, read into the
                    // buffer.
                    result = origdata_decoded;
                    data[0..origdata_decoded] = buffer[readpos..decoded];
                    if(buffer.length - valid < minReadSize)
                    {
                        // move the undecoded data to the front of the buffer,
                        // then read
                        memmove(buffer.ptr, buffer.ptr + decoded, valid - decoded);
                        valid -= decoded;
                        decoded = 0;
                    }
                    // else no need to move, plenty of space in the buffer
                    readpos = decoded;
                    valid += input.read(buffer[valid..$]);
                    assert(valid <= buffer.length);

                    // encode the data
                    if(_decode)
                        decoded += _decode(buffer[decoded..valid]);
                    else
                        decoded = valid;

                    // copy as much decoded data as possible.
                    auto ncopy = decoded - readpos;
                    if(ncopy > data.length)
                        ncopy = data.length;
                    data[origdata_decoded..origdata_decoded+ncopy] =
                        buffer[readpos..readpos+ncopy];
                    readpos += ncopy;

                    // no more decoding needed, shortcut the execution.
                    return result + ncopy;
                }
            }
            else
            {
                // no undecoded data.
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
                        result += input.read(data);
                    }
                    else
                    {
                        // else, fill the buffer.  Even though we will be copying
                        // data, it's probably more efficient than reading small
                        // chunks from the stream.
                        valid = input.read(buffer);
                        if(valid > 0)
                        {
                            // decode the newly read data
                            if(_decode)
                                decoded = _decode(buffer[0..valid]);
                            else
                                decoded = valid;
                            readpos = data.length > decoded ? decoded : data.length;
                            data[0..readpos] = buffer[0..readpos];
                        }
                        else
                        {
                            readpos = decoded = valid = 0;
                        }
                        return result + readpos;
                    }
                }
            }

            // now, we need to possibly decode data that's ready to be
            // returned.
            if(_decode && origdata_decoded < result)
            {
                origdata_decoded += _decode(origdata[origdata_decoded..result]);
                // any data that was not decoded needs to go back to the
                // buffer.
                if(origdata_decoded < result)
                {
                    auto ntocopy = result - origdata_decoded;
                    if(readpos != valid)
                    {
                        // this should only happen if the buffer has enough
                        // space to store the data that wasn't already decoded.
                        assert(readpos >= ntocopy);
                        readpos -= ntocopy;
                        buffer[readpos..readpos + ntocopy] =
                            origdata[origdata_decoded..result];
                    }
                    else
                    {
                        //  no data in the buffer, reset everything
                        buffer[0..ntocopy] = origdata[origdata_decoded..result];
                        readpos = decoded = 0;
                        valid = ntocopy;
                    }
                    result = origdata_decoded;
                }
            }
        }
        return result;
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
    final const(ubyte)[] readUntil(scope size_t delegate(const(ubyte)[] data, size_t start) process)
    {
        // read data from the buffer/stream until the condition is met,
        // expanding the buffer as necessary
        auto d = buffer[readpos..decoded];
        auto status = d.length ? process(d, 0) : ~0;

        // TODO: this simple version always moves data to the front
        // of the buffer if the buffer is filled, but a smarter version
        // could probably only move data when it's most efficient.  We
        // probably need GC support for that.
        if(status == ~0 && readpos > 0)
        {
            memmove(buffer.ptr, buffer.ptr + readpos, valid -= readpos);
            decoded -= readpos;
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
                process(buffer[0..decoded], decoded);
                status = decoded;
            }
            else
            {
                // record the new valid, then use nread to mean the number of
                // newly decoded bytes.
                valid += nread;
                if(_decode)
                    nread = _decode(buffer[decoded..valid]);
                else
                    nread = valid - decoded;
                status = process(buffer[0..decoded + nread], decoded);
                decoded += nread;
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
     * Read until a certain sequence is found.  The returned data includes the
     * sequence.
     */
    final const(ubyte)[] readUntil(const(ubyte)[] lineterm)
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

    /// ditto
    final const(ubyte)[] readUntil(ubyte ub)
    {
        return readUntil((&ub)[0..1]);
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
        auto d = buffer[readpos..decoded];
        size_t status = ~0;
        size_t avalid = 0;
        size_t adecoded = 0;
        if(d.length)
        {
            // see if the buffer satisfies
            status = process(d, 0);
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
            d = buffer[readpos..valid];
            adecoded = decoded - readpos;
            if(arr.length < d.length)
            {
                arr.length = d.length + growSize;
                // make sure we expand to capacity
                arr.length = arr.capacity;
            }
            arr[0..d.length] = d[];
            avalid = d.length;
            // clear out the buffer.
            readpos = valid = decoded = 0;
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
                process(arr[0..adecoded], adecoded);
                status = avalid;
            }
            else
            {
                avalid += nread;
                if(_decode)
                    nread = _decode(arr[adecoded..avalid]);
                else
                    nread = avalid - adecoded;
                if(nread)
                {
                    status = process(arr[0..adecoded + nread], adecoded);
                    adecoded += nread;
                }
            }
        }

        assert(status <= avalid && status <= adecoded);
        // data has been processed, put back any data that wasn't processed.
        auto putback = avalid - status;
        if(buffer.length < putback)
        {
            buffer.length = putback;
        }
        buffer[0..putback] = arr[status..avalid];
        valid = putback;
        decoded = adecoded - status;
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
                if(target < 0 || target > decoded)
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
            readpos = valid = decoded = 0;
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
        return decoded - readpos;
    }

    override void close()
    {
        input.close();
        readpos = valid = decoded = 0;
    }

    /*override void begin() shared
    {
        // no specialized code needed.
    }

    override void end() shared
    {
        // no specialized code needed.
    }*/

    /**
     * The decoder is responsible for transforming data from the correct
     * encoding when reading from a stream.  For instance, a UTF-16 file with
     * byte order different than the native machine will likely need to be
     * byte-swapped as it's read
     */ 
    @property void decoder(size_t delegate(ubyte[] data) dg)
    {
        _decode = dg;
    }

    /**
     * Get the decoder function.
     */
    size_t delegate(ubyte[] data) encoder() @property
    {
        return _decode;
    }

    @property ByChunk byChunk(size_t chunkSize = 0)
    {
        if(chunkSize == 0)
            // default to a reasonable chunk size
            chunkSize = buffer.length / 4;
        return ByChunk(this, chunkSize);
    }
}

class DOutput : BufferedOutput
{
    protected
    {
        // the source stream
        OutputStream _output;

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
        this._output = output;
        this.buffer = new ubyte[bufsize];

        // ensure we aren't wasting any space.
        this.buffer.length = this.buffer.capacity;
    }

    @property OutputStream output()
    {
        return _output;
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
                return _output.tell() + writepos;
            
            // else go to the normal case of simply flushing and seeking.
            // Otherwise, the data we have written to the buffer could be
            // lost.
            goto case Anchor.Begin;

        case Anchor.Begin, Anchor.End:
            // flush the buffer and seek the underlying stream
            flush();
            return _output.seek(delta, whence);

        default:
            // TODO: throw an exception
            return ~0;
        }
    }

    override @property bool seekable() const
    {
        return _output.seekable();
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
        _output.close();
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
            auto nwritten = _output.put(data);
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
    private DInput _input;
    private size_t _size;
    private const(ubyte)[] _curchunk;

    this(InputStream input, size_t size)
    {
        this(new DInput(input), size);
    }

    this(DInput dbi, size_t size)
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
        bool _closeOnDestroy; // do not close stream from destructor
    }

    /**
     */
    this(FILE *source, bool closeOnDestroy = true)
    {
        this.source = source;
        this._closeOnDestroy = !closeOnDestroy;
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
        size_t result = .fread(data.ptr, ubyte.sizeof, data.length, source);
        if(result < data.length)
        {
            // could be error or eof, check error
            if(ferror(source))
                throw new Exception("Error reading");
        }
        return result;
    }

    const(char)[] readln(dchar lineterm)
    {
        auto result = .getdelim(&_buf, &_bufsize, lineterm, source);
        if(result < 0)
            // Throw instead?
            return null;
        return _buf[0..result];
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
        // optimized, just write using fwrite.
        auto result = fwrite(data.ptr, ubyte.sizeof, data.length, source);
        if(result < data.length)
        {
            stderr.writeln("Error writing data: ", result, " ", data.length);
            throw new Exception("Error writing data");
        }
    }

    void flush()
    {
        fflush(source);
    }

    // just in case close isn't called before the GC gets to this object.
    ~this()
    {
        if(!_closeOnDestroy)
            source = null;
        close();
    }

    static CStream open(const char[] name, const char[] mode = "rb")
    {
        return new CStream(.fopen(toStringz(name), toStringz(mode)));
    }
}

/**
 * The width of the text stream
 */
enum StreamWidth : ubyte
{
    /// Determine width from stream itself (valid only for D-based TextInput)
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
enum ByteOrder : ubyte
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
in
{
    assert(charwidth == wchar.sizeof || charwidth == dchar.sizeof);
    assert(data.length % charwidth == 0);
}
body
{
    // depending on the char width, do byte swapping on the data stream.
    switch(charwidth)
    {
    case wchar.sizeof:
        // swap every 2 bytes
        // do majority using uint
        // TODO:  see if this can be optimized further, or if there are
        // better options for 64-bit.
        {
            ushort[] sdata = cast(ushort[])data;
            uint[] idata = cast(uint[])sdata[0..$ - ($ % 2)];
            if(sdata.length % 2 != 0)
            {
                sdata[$-1] = ((sdata[$-1] << 8) & 0xff00) |
                             ((sdata[$-1] >> 8) & 0x00ff);
            }
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
            /*t = ((t << 24) & 0xff000000) |
                ((t << 8)  & 0x00ff0000) |
                ((t >> 8)  & 0x0000ff00) |
                ((t >> 24) & 0x000000ff);*/
            t = bswap(t);
        }
        break;
    default:
        assert(0, "invalid charwidth");
    }
}


// formatted input stream
struct TextInput
{
    private struct Impl
    {
        CStream input_c;
        DInput input_d;
        StreamWidth width;
        ByteOrder bo;

        @property BufferedInput input()
        {
            return input_d ? cast(BufferedInput)input_d : input_c;
        }

        size_t decode(ubyte[] data)
        {
            switch(width)
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
                        width = StreamWidth.UTF16;
                        bo = ByteOrder.Big;
                        goto case StreamWidth.UTF16;
                    }
                    else if(data[0] == 0xFF && data[1] == 0xFE)
                    {
                        // little endian BOM.
                        bo = ByteOrder.Little;
                        if(data[2] == 0 && data[3] == 0)
                        {
                            // most likely this is UTF32
                            width = StreamWidth.UTF32;
                            goto case StreamWidth.UTF32;
                        }
                        // utf-16
                        width = StreamWidth.UTF16;
                        goto case StreamWidth.UTF16;
                    }
                    else if(data[0] == 0 && data[1] == 0 && data[2] == 0xFE && data[3] == 0xFF)
                    {
                        bo = ByteOrder.Big;
                        width = StreamWidth.UTF32;
                        goto case StreamWidth.UTF32;
                    }
                }
                // else this is utf8, bo is ignored.
                width = StreamWidth.UTF8;
                return data.length;// no decoding necessary

            case StreamWidth.UTF8:
                // no decoding necessary.
                return data.length;

            case StreamWidth.UTF16:
                // 
                data = data[0..$-($ % wchar.sizeof)];
                version(LittleEndian)
                {
                    if(bo == ByteOrder.Big)
                        __swapBytes(data, StreamWidth.UTF16);
                }
                else
                {
                    if(bo == ByteOrder.Little)
                        __swapBytes(data, StreamWidth.UTF16);
                }
                return data.length;

            case StreamWidth.UTF32:
                // 
                data = data[0..$-($ % dchar.sizeof)];
                version(LittleEndian)
                {
                    if(bo == ByteOrder.Big)
                        __swapBytes(data, StreamWidth.UTF32);
                }
                else
                {
                    if(bo == ByteOrder.Little)
                        __swapBytes(data, StreamWidth.UTF32);
                }
                return data.length;

            default:
                assert(0, "invalid stream width");
            }
        }

    }

    private Impl* _impl;


    /**
     * Fetch the buffered input stream that backs this text outputter
     */
    @property BufferedInput input()
    in
    {
        assert(_impl);
    }
    body
    {
        return _impl.input;
    }

    void bind(InputStream ins, StreamWidth width = StreamWidth.AUTO, ByteOrder bo = ByteOrder.Native)
    {
        bind(new DInput(ins), width, bo);
    }

    void bind(DInput ins, StreamWidth width = StreamWidth.AUTO, ByteOrder bo = ByteOrder.Native)
    in
    {
        assert(width == StreamWidth.AUTO || width == StreamWidth.UTF8 ||
               width == StreamWidth.UTF16 || width == StreamWidth.UTF32);
        assert(bo == ByteOrder.Native || bo == ByteOrder.Little ||
               bo == ByteOrder.Big);
    }
    body
    {
        if(!_impl)
            _impl = new Impl;

        ins.decoder = &_impl.decode;
        _impl.bo = bo;
        _impl.input_d = ins;
        _impl.width = width;
    }

    void bind(FILE *fp)
    {
        bind(new CStream(fp));
    }

    void bind(CStream cstr)
    {
        if(!_impl)
            _impl = new Impl;
        _impl.input_c = cstr;
        _impl.width = StreamWidth.UTF8;
    }

    private static size_t checkLineT(T)(const(ubyte)[] ubdata, size_t start, dchar terminator)
    {
        auto data = cast(const(T)[])ubdata;
        start /= T.sizeof;
        bool done = false;
        foreach(size_t idx, dchar d; data[start..$])
        {
            if(done)
                return idx;
            if(d == terminator)
                // need to go one more index.
                done = true;
        }
        return done ? data.length * T.sizeof: ~0;
    }

    private immutable(T)[] transcode(T, U)(const(ubyte)[] data)
    {
        return to!(immutable(T)[])(cast(const(U)[])data);
    }

    const(T)[] readln(T = char)(dchar terminator = '\n') if(is(T == char) || is(T == wchar) || is(T == dchar))
    {
        if(_impl.input_d)
        {
            // use the d_input function to read until a line terminator is
            // found.
            size_t checkLine(const(ubyte)[] data, size_t start)
            {
                // the "character" we are looking for is determined by the
                // width.
                switch(_impl.width)
                {
                case StreamWidth.UTF8:
                    return checkLineT!char(data, start, terminator);
                case StreamWidth.UTF16:
                    return checkLineT!wchar(data, start, terminator);
                case StreamWidth.UTF32:
                    return checkLineT!dchar(data, start, terminator);
                default:
                    assert(0, "invalid character width");
                }
            }
            const(ubyte)[] result = din.readUntil(&checkLine);
            if(_impl.width == T.sizeof)
            {
                return cast(const(T)[])result;
            }
            else
            {
                switch(_impl.width)
                {
                case StreamWidth.UTF8:
                    return transcode!(T, char)(result);
                case StreamWidth.UTF16:
                    return transcode!(T, wchar)(result);
                case StreamWidth.UTF32:
                    return transcode!(T, dchar)(result);
                default:
                    assert(0, "invalid character width");
                }
            }
        }
        else
        {
            // C input, must be UTF8
            assert(_impl.input_c);
            auto line = _impl.input_c.readln(terminator);
            if(line.length)
            {
                static if(is(T == char))
                    return line;
                else
                    return to!(immutable(T)[])(line);
            }
            else
                // no data, no need to do any allocation, etc.
                return (T[]).init;
        }
    }
}

/*struct ByLine(Char, Terminator)
{
    BufferedInput input;
    Char[] line;
    Terminator terminator;
    KeepTerminator keepTerminator;
}*/

// formatted output stream
//
// Note, this should never be on the stack, it should only ever be allocated on
// the heap or in the global segment.
struct TextOutput
{
    private struct Impl
    {
        // the actual buffered output stream.
        BufferedOutput output;

        // this is settable at runtime because the interface to a text stream
        // is independent of the character width being sent to it.  Otherwise,
        // it would not be possible to say, for example, change the output
        // width to wchar for stdou.
        ubyte charwidth;

        void encode(ubyte[] data)
        {
            __swapBytes(data, charwidth);
        }

        ptrdiff_t flushLineCheckT(T)(const(T)[] data)
        {
            for(const(T)* i = data.ptr + data.length - 1; i >= data.ptr; --i)
            {
                if(*i == cast(T)'\n')
                    return (i - data.ptr + 1) * T.sizeof;
            }
            return -1;
        }

        ptrdiff_t flushLineCheck(const(ubyte)[] data)
        {
            switch(charwidth)
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

    }

    // the implementation pointer.
    private Impl* _impl;

    /**
     * Fetch the buffered output stream that backs this text outputter
     */
    @property BufferedOutput output()
    {
        return _impl.output;
    }

    void bind(OutputStream outs, StreamWidth width = StreamWidth.UTF8, ByteOrder bo = ByteOrder.Native)
    {
        bind(new DOutput(outs), width, bo);
    }

    void bind(DOutput dbo, StreamWidth width = StreamWidth.UTF8, ByteOrder bo = ByteOrder.Native)
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
        if(!_impl)
            _impl = new Impl;

        if(width != StreamWidth.UTF8)
        {
            version(LittleEndian)
            {
                if(bo == ByteOrder.Big)
                    dbo.encoder = &_impl.encode;
                else
                    dbo.encoder = null;
            }
            else
            {
                if(bo == ByteOrder.Little)
                    dbo.encoder = &_impl.encode;
                else
                    dbo.encoder = null;
            }
        }

        if(auto f = cast(File)dbo.output)
        {
            // this is a device stream, check to see if it's a terminal
            version(Posix)
            {
                if(isatty(f.handle))
                {
                    // by default, do a flush check based on a newline
                    dbo.flushCheck = &_impl.flushLineCheck;
                }
            }
            else
                static assert(0, "Unsupported OS");
        }
        bindImpl(dbo, width);
    }

    void bind(FILE *outs)
    {
        bindImpl(new CStream(outs), StreamWidth.UTF8);
    }

    void bind(CStream cstr)
    {
        bindImpl(cstr, StreamWidth.UTF8);
    }

    private void bindImpl(BufferedOutput outs, StreamWidth width = StreamWidth.UTF8)
    in
    {
        assert(width == StreamWidth.UTF8 || width == StreamWidth.UTF16 ||
               width == StreamWidth.UTF32);
    }
    body
    {
        if(!_impl)
            _impl = new Impl;
        this._impl.output = outs;
        this._impl.charwidth = width;
    }

    void write(S...)(S args)
    in
    {
        assert(_impl !is null);
    }
    body
    {
        switch(_impl.charwidth)
        {
        case StreamWidth.UTF8:
            priv_write!(char)(args);
            break;
        case StreamWidth.UTF16:
            priv_write!(wchar)(args);
            break;
        case StreamWidth.UTF32:
            priv_write!(dchar)(args);
            break;
        default:
            assert(0);
        }
    }

    void writeln(S...)(S args)
    in
    {
        assert(_impl !is null);
    }
    body
    {
        switch(_impl.charwidth)
        {
        case StreamWidth.UTF8:
            priv_write!(char)(args, '\n');
            break;
        case StreamWidth.UTF16:
            priv_write!(wchar)(args, '\n');
            break;
        case StreamWidth.UTF32:
            priv_write!(dchar)(args, '\n');
            break;
        default:
            assert(0);
        }
    }

    private void priv_write(C, S...)(S args)
    {
        //_output.begin();
        auto w = OutputRange!C(_impl.output);

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
        switch(_impl.charwidth)
        {
        case StreamWidth.UTF8:
            priv_writef!(char, false)(args);
            break;
        case StreamWidth.UTF16:
            priv_writef!(wchar, false)(args);
            break;
        case StreamWidth.UTF32:
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
        switch(_impl.charwidth)
        {
        case StreamWidth.UTF8:
            priv_writef!(char, true)(args);
            break;
        case StreamWidth.UTF16:
            priv_writef!(wchar, true)(args);
            break;
        case StreamWidth.UTF32:
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
        auto w = OutputRange!C(_impl.output);
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
                static if(is(CT == char))
                {
                    // convert the character to utf8
                    char[4] buf = void;
                    output.put(cast(ubyte[])std.utf.toUTF8(buf, c));
                }
                else static if(is(CT == wchar))
                {
                    // convert the character to utf16
                    wchar[2] buf = void;
                    output.put(cast(ubyte[])std.utf.toUTF16(buf, c));
                }
                else static if(is(CT == dchar))
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
    in
    {
        assert(_impl);
    }
    body
    {
        _impl.output.flush();
    }

    void close()
    in
    {
        assert(_impl);
    }
    body
    {
        if(_impl && _impl.output)
        {
            _impl.output.close();
            _impl.output = null;
        }
    }

    /**
     * Writes a BOM to the stream unless the stream is UTF8.  If force flag is
     * set to true, a UTF8 BOM is still written.
     */
    void writeBOM(bool force = false)
    in
    {
        assert(_impl);
    }
    body
    {
        if(force || _impl.charwidth != StreamWidth.UTF8)
        {
            write(cast(dchar)0xFEFF);
        }
    }
}

/**
 * Open a buffered file stream according to the mode string.  The mode string
 * is a template argument to allow returning different types based on the mode.
 *
 * The mode string follows the conventions of File.open
 *
 * Note that if mode indicates the stream is read and write (i.e. it contains a
 * '+'), a tuple(input, output) is returned.
 */
auto openFile(string mode = "rb")(string fname)
{
    auto base = File.open(fname, mode);
    static if(mode == "r" || mode == "rb")
        return new DInput(base);
    else static if(mode == "w" || mode == "a" || mode == "wb" || mode == "ab")
        return new DOutput(base);
    else static if(mode == "w+" || mode == "r+" || mode == "a+" || 
                   mode == "w+b" || mode == "r+b" || mode == "a+b" || 
                   mode == "wb+" || mode == "rb+" || mode == "ab+")
        return tuple(new DInput(base), new DOutput(base));
    else
        static assert(0, "mode not supported for openFile: " ~ mode);
}

//TODO: make these shared.
__gshared {

    // Raw unbuffered i/o streams.
    // TODO: need better names for these
    File rawdin;
    File rawdout;
    File rawderr;

    // Buffered  i/o streams
    DInput din;
    DOutput dout;
    DOutput derr;

    // Text i/o
    TextInput stdin;
    TextOutput stdout;
    TextOutput stderr;
}

shared static this()
{
    version(linux)
    {
        din = new DInput(rawdin = new File(0, false));
        dout = new DOutput(rawdout = new File(1, false));
        derr = new DOutput(rawderr = new File(2, false));
    }
    else
        static assert(0, "Unsupported OS");

    // set up the shared buffered streams
    stdin.bind(din);
    stdout.bind(dout);
    stderr.bind(derr);
}

@property 
shared static ~this()
{
    // we could possibly close, but since these are the main output streams,
    // we'll just flush the buffers.
    stdout.flush();
    stderr.flush();
}

void useCStdio()
{
    stdin.bind(new CStream(core.stdc.stdio.stdin, false));
    stdout.bind(new CStream(core.stdc.stdio.stdout, false));
    stderr.bind(new CStream(core.stdc.stdio.stderr, false));
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
    stdout.write(args);
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
    stdout.writeln(args);
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
    stdout.writef(args);
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
    stdout.writefln(args);
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

