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
import std.exception;

// This uses inline utf decoding/encoding instead of calling runtime functions.
version = inlineutf;

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
interface Seekable
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
     * after seeking, or ulong.max if this cannot be determined.
     */
    ulong seek(long delta, Anchor whence=Anchor.Begin);

    /**
     * Determine the current file position.
     *
     * Returns ulong.max if the operation fails or is not supported.
     */
    final ulong tell() {return seek(0, Anchor.Current); }

    /**
     * returns: false if the stream cannot be seeked, true if it can.  True
     * does not mean that a given seek call will succeed.
     */
    @property bool seekable();
}

/**
 * An input stream.  This is the simplest interface to a stream.  An
 * InputStream provides no buffering or high-level constructs, it's simply an
 * abstraction of a low-level stream mechanism.
 */
interface InputStream : Seekable
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

/**
 * simple output interface.
 */
interface OutputStream : Seekable
{
    /**
     * Write a chunk of data to the output stream
     *
     * params:
     * data = The buffer to write to the stream.
     * returns: the number of bytes written on success.  If 0 is returned, then
     * the stream cannot be written to.
     */
    size_t put(const(ubyte)[] data);
    /// ditto
    alias put write;

    /**
     * Close the stream.  This releases any resources from the object.
     */
    void close();
}

/**
 * The basic device-based Input and Output stream.  This uses the OS's native
 * file handle to communicate using physical devices.
 */
class File : InputStream, OutputStream
{
    private
    {
        // the file descriptor
        // fd is set to -1 when the stream is closed
        int fd = -1;

        // -1 = can't seek, 1 = can seek, 0 = uninitialized
        byte _canSeek = 0;

        // flag indicating the destructor should close the stream. Used
        // when a File does not own the fd in question (set to false).
        bool _closeOnDestroy;
    }

    /**
     * Construct an input stream based on the file descriptor
     *
     * params:
     * fd = The file descriptor to wrap
     * closeOnDestroy = If set to true, the destructor will close the file
     * descriptor.  This does not affect the operation of close.
     */
    this(int fd, bool closeOnDestroy = true)
    {
        this.fd = fd;
        this._closeOnDestroy = closeOnDestroy;
    }

    /**
     * Open a file.  the specification for mode is identical to the linux man
     * page for fopen
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
     * after seeking.
     */
    long seek(long delta, Anchor whence=Anchor.Begin)
    {
        auto retval = .lseek64(fd, delta, cast(int)whence);
        if(retval == -1)
        {
            // TODO: probably need an I/O exception
            throw new Exception("seek failed, check errno");
        }
        return retval;
    }

    /**
     * returns: false if the stream cannot be seeked, true if it can.  True
     * does not mean that a given seek call will succeed, it depends on the
     * implementation/environment.
     */
    @property bool seekable()
    {
        // by default, we return true, because we cannot determine if a generic
        // file descriptor can be seeked.
        if(!_canSeek)
        {
            _canSeek = .lseek64(fd, 0, Anchor.Current) == -1 ? -1 : 1;
        }
        return _canSeek > 0;
    }

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

    /**
     * Write a chunk of data to the output stream
     *
     * returns the number of bytes written on success.
     *
     * If 0 is returned, then the stream cannot be written to.
     */
    size_t put(const(ubyte)[] data)
    {
        auto result = core.sys.posix.unistd.write(fd, data.ptr, data.length);
        if(result < 0)
        {
            // Should we check for EPIPE?  Not sure.
            //if(errno == EPIPE)
            //  return 0;
            throw new Exception("write failed, check errno");
        }
        return cast(size_t)result;
    }

    /// ditto
    alias put write;

    /**
     * Close the stream.  This releases any resources from the object.
     */
    void close()
    {
        if(fd != -1 && .close(fd) < 0)
            throw new Exception("close failed, check errno");
        fd = -1;
    }

    /**
     * Destructor.  This is used as a safety net, in case the stream isn't
     * closed before being destroyed in the GC.  It is recommended to close
     * deterministically using close, because there is no guarantee the GC will
     * call this destructor.
     */
    ~this()
    {
        if(_closeOnDestroy && fd != -1)
        {
            // can't check this for errors, because we can't throw in a
            // destructor.
            .close(fd);
        }
        fd = -1;
    }

    /**
     * Get the OS-specific handle for this File
     */
    @property int handle()
    {
        return fd;
    }
}

/**
 * D buffered input stream.
 *
 * This object wraps a source InputStream with a buffering system implemented
 * purely in D.
 */
final class DInput : Seekable
{
    private
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
     *
     * params:
     *
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

    /**
     * Read bytes into a buffer.  Note that this may copy data to an internal
     * buffer first before copying to the parameter.  However, every attempt is
     * made to minimize the double-buffering.
     *
     * params:
     * data = The location to read the data to.
     *
     * Returns: the number of bytes read. 0 means EOF, nonzero but less than
     * data.length does NOT indicate EOF.
     */
    size_t read(ubyte[] data)
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
     * Reads as much data as possible from the stream.  This differs from read
     * in that it will continue reading until either EOF is reached, or data is
     * filled.
     *
     * This throws an exception on any error.
     *
     * params:
     * data = The data buffer to fill.
     *
     * returns: the data read as a slice of the original buffer.  If the length
     * is less than the original data length, EOF was reached.
     */
    ubyte[] readComplete(ubyte[] data)
    {
        size_t filled = 0;
        while(filled < data.length)
        {
            auto nread = read(data[filled..$]);
            if(nread == 0)
                break;
            filled += nread;
        }
        return data[0..filled];
    }
    
    /**
     * Read data until a condition is satisfied.
     *
     * Buffers data from the input stream until the delegate returns other than
     * size_t.max.  The delegate is passed the data read so far, and the start
     * of the data just read.  The deleate should return size_t.max if the
     * condition is not satisfied, or the number of bytes that should be
     * consumed otherwise.
     *
     * When no more bytes can be read, the delegate will be called with start
     * == data.length.  The delegate has the option of returning size_t.max,
     * which means, return the data read so far.  Or it can return a valid
     * status, which means only that data will be read.
     *
     * If the delegate returns 0, then 0 bytes will be returned, and no data
     * will be consumed.  You can use this to peek at data.
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
        debug(stdio) printf("readUntil, readpos=%d, decoded=%d, valid=%d, buffer.length=%d\n", readpos, decoded, valid, buffer.length);
        // read data from the buffer/stream until the condition is met,
        // expanding the buffer as necessary
        auto d = buffer[readpos..decoded];
        auto status = d.length ? process(d, 0) : size_t.max;

        // TODO: this simple version always moves data to the front
        // of the buffer if the buffer needs to be filled, but a smarter
        // version could probably only move data when it's most efficient.
        if(status == size_t.max && readpos > 0)
        {
            if((valid -= readpos) > 0)
                memmove(buffer.ptr, buffer.ptr + readpos, valid);
            decoded -= readpos;
            readpos = 0;
        }

        while(status == size_t.max)
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
                if(decoded > 0)
                    status = process(buffer[0..decoded], decoded);
                if(status == size_t.max)
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
        debug(stdio) printf("readUntil (after while), readpos=%d, decoded=%d, valid=%d\n", readpos, decoded, valid);

        // adjust the read buffer, and return the data.

        auto ep = readpos + status;
        d = buffer[readpos..ep];
        if(ep == valid)
            valid = readpos = decoded = 0;
        else
            readpos = ep;
        return d;
    }

    /**
     * Read until a certain sequence of bytes is found.
     *
     * params:
     * term = The byte sequence that terminates the read.
     *
     * returns: The data read.  The data includes the termination sequence.
     */
    const(ubyte)[] readUntil(const(ubyte)[] term)
    {
        immutable lastbyte = term[$-1];
        auto ltend = term.ptr + term.length - 1;
        size_t _checkDelim1(const(ubyte)[] data, size_t start)
        {
            auto ptr = data.ptr + start;
            auto end = data.ptr + data.length;
            for(;ptr < end; ++ptr)
            {
                if(*ptr == lastbyte)
                    break;
            }
            return ptr == end ? size_t.max : ptr - data.ptr + 1;
        }

        size_t _checkDelimN(const(ubyte)[] data, size_t start)
        {
            if(start <= term.length - 1)
                start = term.length - 1;
            // TODO; can try optimizing this
            auto ptr = data.ptr + start;
            auto end = data.ptr + data.length;
            for(;ptr < end; ++ptr)
            {
                if(*ptr == lastbyte)
                {
                    // triggers a check
                    auto ptr2 = ptr - term.length + 1;
                    auto ltptr = term.ptr;
                    for(; ltptr < ltend; ++ltptr, ++ptr2)
                        if(*ltptr != *ptr2)
                            break;
                    if(ltptr == ltend)
                        break;
                }
            }
            return ptr >= end ? size_t.max : ptr - data.ptr + 1;
        }

        return term.length == 1 ? readUntil(&_checkDelim1) : readUntil(&_checkDelimN);
    }

    /// ditto
    const(ubyte)[] readUntil(ubyte ub)
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
        size_t status = size_t.max;
        size_t avalid = 0;
        size_t adecoded = 0;
        if(d.length)
        {
            // see if the buffer satisfies
            status = process(d, 0);
            if(status != size_t.max)
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


        while(status == size_t.max)
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
                status = process(arr[0..adecoded], adecoded);
                if(status == size_t.max)
                    status = adecoded;
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
            // always use up all available space.
            buffer.length = buffer.capacity;
        }
        buffer[0..putback] = arr[status..avalid];
        valid = putback;
        decoded = adecoded - status;
        readpos = 0;
        return status;
    }

    /**
     * Skips buffered bytes.
     *
     * params:
     * nbytes = The number of bytes to skip.
     *
     * Returns the number of bytes skipped.  This may be less than the
     * parameter if the buffer does not have nbytes readable bytes.
     */
    size_t skip(size_t nbytes)
    {
        auto remaining = decoded - readpos;
        if(nbytes > remaining)
            nbytes = remaining;
        readpos += nbytes;
        return nbytes;
    }

    /**
     * Seek a buffered stream.
     *
     * This behaves exactly as Seekable.seek describes, except for the
     * additional feature that if you seek within the buffer, the function
     * succeeds even if the underlying device is not seekable.
     *
     * Therefore, even if seekable returns false, it's still possible to seek
     * within the buffer.
     *
     * params:
     * delta = The number of bytes to seek from the given anchor.
     * whence = The anchor from whence to seek.
     * 
     * returns: The position of the stream if the underlying device is
     * seekable.  If if a buffer seek is performed, but the underlying device
     * does not support seeking, ulong.max is returned.
     */
    ulong seek(long delta, Anchor whence=Anchor.Begin)
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
                return ulong.max;
            }

        case Anchor.Begin, Anchor.End:
            // reset the buffer and seek the underlying stream
            readpos = valid = decoded = 0;
            return input.seek(delta, whence);

        default:
            assert(0, "Invalid anchor");
        }
    }

    /**
     * Is this stream seekable?
     *
     * returns: true if the underlying device is seekable.  Note that even if
     * the underlying device is not seekable, buffer seeking is still allowed.
     */
    @property bool seekable()
    {
        return input.seekable();
    }

    /**
     * Get the size of the valid data in the buffer.  Note that the buffer
     * may be larger than this, and the number of bytes read from the stream
     * may even be larger.  This denotes the seekable range of the buffer.
     */
    @property size_t bufsize()
    {
        return decoded;
    }

    /**
     * The number of bytes readable in the buffer.  If one reads this many
     * bytes, no data will be read from the device.  Also you can skip this
     * many bytes ahead or seek this many bytes ahead without invalidating the
     * buffer.
     */
    @property size_t readable()
    {
        return decoded - readpos;
    }

    /**
     * Close the input device.  It is recommended to do this instead of letting
     * the GC close the device because the GC is not guaranteed to run the
     * device's destructor.
     */
    void close()
    {
        input.close();
        readpos = valid = decoded = 0;
    }

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
     * Get the decoder delegate.
     */
    size_t delegate(ubyte[] data) encoder() @property
    {
        return _decode;
    }

    /**
     * Get a range on this input stream based on the size of the chunks to be
     * read.
     *
     * params:
     * chunkSize = The size of the chunk to get.  If 0 is passed in, a default
     * size is used.
     *
     * returns:  A ByChunk object which will iterate over the stream in chunks
     * of size chunkSize.
     */
    ByChunk byChunk(size_t chunkSize = 0)
    {
        if(chunkSize == 0)
            // default to a reasonable chunk size
            chunkSize = buffer.length / 4;
        return ByChunk(this, chunkSize);
    }

    /**
     * Get the underlying input stream for this buffered stream.
     */
    @property InputStream unbuffered()
    {
        return input;
    }
}

/**
 * The D buffered output stream.  This class wraps an output stream with
 * buffering capability implemented purely in D.
 */
final class DOutput : Seekable
{
    private
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
        size_t delegate(ubyte[] data) _encode;

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

    /**
     * Get the unbuffered output stream for this DOutput.
     */
    @property OutputStream unbuffered()
    {
        return _output;
    }

    /+ commented out for now, not sure how shared classes are going to work for I/O
    void begin()
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

    void end()
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

                ensureWrite(buffer[0..endpos]);

                // now, we need to move the data to the front of the buffer
                // this is the only place we have to do this.
                if(writepos != endpos)
                    memmove(buffer.ptr, buffer.ptr + endpos, writepos - endpos);
                writepos -= endpos;
            }
        }
        _startofwrite = 0;
    } +/

    /**
     * Write data to the buffered stream.
     *
     * Throws an exception on error.  All data will be written to the stream,
     * unless an error occurs.  If an error occurs, there is no indication of
     * how many bytes were written.
     *
     * params:
     * data = The data to write.
     */
    void put(const(ubyte)[] data)
    {
        if(!data.length)
            return;
        // determine if any data should be flushed before writing.
        auto fcheck = !_noflushcheck && _flushCheck ? _flushCheck(data) : -1;
        assert(fcheck <= cast(ptrdiff_t)data.length);
        // minwrite is the number of bytes that must be written to the
        // stream.
        ptrdiff_t minwrite = (fcheck < 0) ? 0 : fcheck + writepos;
        if(minwrite > 0 || writepos + data.length >= buffer.length)
        {
            if(writepos + data.length - minwrite >= buffer.length)
            {
                // minwrite is not needed, we are going to have to flush more
                // than minwrite bytes anyways.
                minwrite = 0;
            }
            // need to write some data to the actual stream. But we want to
            // minimize the calls to output.put.
            if(_encode)
            {
                // simple case, everything must be buffered and encoded before
                // its written, so just do that in a loop.  This handles all
                // possible values of minwrite and whether there is data in the
                // buffer already.
                while(data.length + writepos >= buffer.length)
                {
                    // already data in the buffer, this is a special case, we
                    // can optimize the rest in the loop.
                    auto ntoCopy = buffer.length - writepos;
                    auto totalbytes = writepos + ntoCopy;
                    buffer[writepos..totalbytes] = data[0..ntoCopy];
                    data = data[ntoCopy..$];
                    auto nencoded = _encode(buffer[0..totalbytes]);
                    //printf("nencoded = %u, totalbytes=%u\n", nencoded, totalbytes);
                    ensureWrite(buffer[0..nencoded]);
                    if(totalbytes != nencoded)
                    {
                        // need to move the non-encoded bytes to the front of
                        // the buffer
                        writepos = totalbytes - nencoded;
                        _startofwrite = nencoded > _startofwrite ? 0 :
                            _startofwrite - nencoded;
                        memmove(buffer.ptr, buffer.ptr + nencoded, writepos);
                    }
                    else
                    {
                        writepos = _startofwrite = 0;
                    }
                    minwrite -= nencoded;
                }

                if(minwrite > 0)
                {
                    // still have some data left to write
                    auto ntoCopy = minwrite - writepos;
                    buffer[writepos..minwrite] = data[0..ntoCopy];
                    auto ndecoded = _encode(buffer[0..minwrite]);
                    assert(ndecoded == minwrite); // nowhere to go if this isn't true.
                    ensureWrite(buffer[0..minwrite]);
                    buffer[0..data.length - ntoCopy] = data[ntoCopy..$];
                    writepos = data.length - ntoCopy;
                    // TODO: not sure about this...
                    _startofwrite = 0;
                }
                else
                {
                    // copy whatever is left over.
                    if(data.length)
                    {
                        buffer[writepos..writepos + data.length] = data[];
                        writepos += data.length;
                    }
                }
                //printf("here, writepos=%d\n", writepos);
            }
            else
            {
                // keep looping until there is no data left
                while(data.length > 0)
                {
                    if(writepos) // still data in the buffer
                    {
                        if(writepos + data.length < buffer.length)
                        {
                            // determine whether to write based on minwrite
                            if(minwrite > 0)
                            {
                                auto ntoCopy = minwrite - writepos;
                                buffer[writepos..minwrite] = data[0..ntoCopy];
                                ensureWrite(buffer[0..minwrite]);
                                // no more data in the buffer
                                writepos = 0;
                                data = data[ntoCopy..$];
                                minwrite = 0;
                            }
                            else
                            {
                                // no requirement to flush, just output the
                                // rest of the data to the buffer.
                                buffer[writepos..writepos+data.length] = data[];
                                writepos += data.length;
                                data = null;
                            }
                        }
                        else
                        {
                            // going to need at least one write.
                            if(minwrite > 0 && minwrite <= buffer.length)
                            {
                                // copy enough to satisfy minwrite, then we
                                // reduce to the simple case.
                                buffer[writepos..minwrite] = data[0..minwrite - writepos];
                                ensureWrite(buffer[0..minwrite]);
                                // update state
                                data = data[minwrite - writepos..$];
                                minwrite = 0;
                                writepos = 0;
                            }
                            else
                            {
                                // need to write at least a buffer's worth of
                                // data.  Buffer as much as possible, and write
                                // it.  Subsequent writes may write directly
                                // from data.
                                auto ntoCopy = buffer.length - writepos;
                                buffer[writepos..$] = data[0..ntoCopy];
                                ensureWrite(buffer);

                                // update state
                                data = data[ntoCopy..$];
                                minwrite -= buffer.length;
                                writepos = 0;
                            }
                        }
                    }
                    else
                    {
                        // no data in the buffer.  See how much data should be
                        // written directly.
                        if(minwrite > 0)
                        {
                            auto nwritten = _output.put(data[0..minwrite]);
                            minwrite -= nwritten;
                            data = data[nwritten..$];
                        }
                        else if(data.length >= buffer.length)
                        {
                            auto nwritten = _output.put(data);
                            data = data[nwritten..$];
                        }
                        else
                        {
                            // data will fit in the buffer, do it.
                            buffer[0..data.length] = data[];
                            writepos = data.length;
                            data = null;
                        }
                    }
                }
            }
        }
        else
        {
            // no data needs to be written to the stream, just buffer
            // everything.
            if(data.length <= 4)
            {
                // do not use the runtime, that is overkill.
                auto p = data.ptr;
                auto e = data.ptr + data.length;
                while(p != e)
                    buffer[writepos++] = *p++;
            }
            else
            {
                buffer[writepos..writepos + data.length] = data[];
                writepos += data.length;
            }
        }
    }

    /**
     * Seek the buffered output.
     *
     * Any seek besides to the current position will flush any unwritten data
     * to the device.  Unlike DInput, DOutput does not allow buffer seeking, to
     * avoid complex situations.
     *
     * params:
     * delta = The offset from the anchor to seek.
     * whence = The anchor to offset from for determining the seek position.
     *
     * returns: The stream position after performing the seek.
     */
    ulong seek(long delta, Anchor whence=Anchor.Begin)
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
            throw new Exception("invalid anchor");
        }
    }

    /**
     * Is this buffered stream seekable?
     *
     * Returns: true if the underlying device is seekable.
     */
    @property bool seekable()
    {
        return _output.seekable();
    }

    /**
     * How large the buffer is.
     *
     * returns: the size of the buffer.
     */
    @property size_t bufsize()
    {
        return buffer.length;
    }

    /**
     * How many bytes are ready to be written to the stream.
     *
     * Note that in certain cases, the data cannot all be encoded, so it may
     * not all be written on a flush.
     *
     * returns: the number of bytes ready to write.
     */
    @property size_t readyToWrite()
    {
        return writepos;
    }

    /**
     * Close the stream.
     *
     * Note, if you do not call this function, the unwritten data will NOT be
     * flushed to the stream.  This is due to the non-deterministic behavior of
     * the GC.  It's highly recommended to call this function when you are done
     * with a DOutput object.
     */
    void close()
    {
        flush();
        _output.close();
    }

    /**
     * Flush the stream.  This outputs all buffered data so far to the device.
     *
     * Note that if some data cannot be encoded, it will not be written to the
     * device, but will be moved to the front of the buffer for the next write.
     */
    void flush()
    {
        if(writepos)
        {
            if(_encode)
            {
                auto nencoded = _encode(buffer[0..writepos]);
                ensureWrite(buffer[0..nencoded]);
                if(writepos != nencoded)
                {
                    // need to move the non-encoded bytes to the front of
                    // the buffer
                    writepos -= nencoded;
                    _startofwrite = nencoded > _startofwrite ? 0 :
                        _startofwrite - nencoded;
                    memmove(buffer.ptr, buffer.ptr + nencoded, writepos);
                }
                else
                {
                    writepos = _startofwrite = 0;
                }
            }
            else
            {
                ensureWrite(buffer[0..writepos]);
                writepos = _startofwrite = 0;
            }
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
     * The return value will be ignored if the total data exceeds the buffer
     * size.  In this case, the data must be flushed to not overrun the buffer.
     *
     * params:
     * dg = The above described delegate.  To restore the basic flush checker
     * (i.e. only flush on buffer full), set this to null.
     */
    @property void flushCheck(ptrdiff_t delegate(const(ubyte)[] newData) dg)
    {
        _flushCheck = dg;
    }

    /**
     * Get the buffer flush checker.  This delegate determines whether the
     * buffer should be flushed immediately after a write.  If this routine is
     * not set, the default is to flush after the buffer is full.
     *
     * Returns: the above described delegate, or null if the default checker is
     * being used.
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
    @property void encoder(size_t delegate(ubyte[] data) dg)
    {
        _encode = dg;
    }

    /**
     * Get the encoder function.
     */
    size_t delegate(ubyte[] data) encoder() @property
    {
        return _encode;
    }

    // repeatedly write to the device until the data has all been written.  The
    // expectation is that the buffer size will make this mostly only write
    // once.
    private size_t ensureWrite(const(ubyte)[] data)
    {
        // write in a loop until the minimum data is written.
        size_t result;
        while(data.length > 0)
        {
            auto nwritten = _output.put(data);
            if(!nwritten) // eof
                break;
            result += nwritten;
            data = data[nwritten..$];
        }
        return result;
    }
}

/**
 * Range which reads data in chunks from an input stream.  It relies on
 * buffered input, so if you give it an unbuffered stream, it will construct a
 * buffer around it.
 *
 * Note that if you are using ByChunk and some other mechanism to read the same
 * buffered stream, the range element might be corrupted.  In other words,
 * using the buffered stream can make the current chunk invalid.
 */
struct ByChunk
{
    private
    {
        DInput _input;
        size_t _size;
        const(ubyte)[] _curchunk;
    }

    this(InputStream input, size_t size)
    {
        this(new DInput(input), size);
    }

    this(DInput dbi, size_t size)
    in
    {
        assert(size, "size must be greater than zero");
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
        return data.length >= _size ? _size : size_t.max;
    }

    /**
     * Close the input stream forcibly
     */
    void close()
    {
        _input.close();
    }
}

/**
 * C buffered input/output stream.  This wraps a C FILE * object.
 */
final class CStream : Seekable
{
    private
    {
        FILE *source;
        char *_buf; // C malloc'd buffer used to support getDelim
        size_t _bufsize; // size of buffer
        bool _closeOnDestroy; // do not close stream from destructor
        byte _canSeek;
    }

    /**
     * Constructor.
     *
     * params:
     * source = The FILE * stream to wrap.
     * closeOnDestroy = True if you want the destructor of this object to close
     * the wrapped stream.
     */
    this(FILE *source, bool closeOnDestroy = true)
    {
        this.source = source;
        this._closeOnDestroy = closeOnDestroy;
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
     * after seeking, or ulong.max if this cannot be determined.
     */
    ulong seek(long delta, Anchor whence=Anchor.Begin)
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

    /**
     * returns: false if the stream cannot be seeked, true if it can.  True
     * does not mean that a given seek call will succeed.
     */
    @property bool seekable()
    {
        if(!_canSeek)
        {
            _canSeek = .ftell(source) == -1 ? -1 : 1;
        }
        return _canSeek > 0;
    }

    /**
     * Read data from the stream.
     *
     * params:
     * data = The buffer to read data into.
     * returns: less than data.length on eof, otherwise, number of bytes read.
     */
    size_t read(ubyte[] data)
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

    /**
     * Read a line of data from the stream.  You can dictate what character to
     * use for line termination.
     * params:
     * lineterm = The character to use to detect an end of line.
     * returns: The line of data from the stream, including the delimiter if
     * found.
     */
    const(char)[] readln(dchar lineterm)
    {
        auto result = .getdelim(&_buf, &_bufsize, lineterm, source);
        if(result < 0)
            // TODO: Throw instead?
            return null;
        return _buf[0..result];
    }

    /**
     * Get the underlying FILE*.
     */
    @property FILE *cFile()
    {
        return source;
    }

    /**
     * Close the stream.  This will be done by the GC if you do not call it
     * manually, but it is highly recommended to call this manually, as the GC
     * is not guaranteed to run destructors.
     */
    void close()
    {
        if(source)
           fclose(source);
        source = null;
        if(_buf)
            .free(_buf);
        _buf = null;
        _bufsize = 0;
    }

    /**
     * Write data to the stream.
     * 
     * if not all the data could be written, an exception is thrown.
     */
    void put(const(ubyte)[] data)
    {
        // optimized, just write using fwrite.
        auto result = fwrite(data.ptr, ubyte.sizeof, data.length, source);
        if(result < data.length)
        {
            throw new Exception("Error writing data");
        }
    }

    /// ditto
    alias put write;

    /**
     * Write a single dchar to the stream (calls fputc)
     */
    void putc(dchar data)
    {
        fputc(data, source);
    }

    /**
     * Flush all the unwritten data to the underlying device (calls fflush)
     */
    void flush()
    {
        fflush(source);
    }

    /**
     * Destructor.  If the object is set to close the stream, it is done.
     */
    ~this()
    {
        if(!_closeOnDestroy)
            source = null;
        close();
    }

    /**
     * Open a file as a CStream using the given file mode
     *
     * params:
     * name = The name of the file to open.
     * mode = The mode to open the file with (passed unchanged to fopen).
     * returns: A new CStream opened with the given file.
     */
    static CStream open(const char[] name, const char[] mode = "rb")
    {
        auto f = .fopen(toStringz(name), toStringz(mode));
        if(f)
            return new CStream(f);
        throw new Exception("Error opening file");
    }
}

/**
 * The width of a text stream
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
    UTF32 = 4,

    /// flag indicating the BOM should be kept if it's in the stream (valid
    /// only for D-based TextInput)
    KEEP_BOM = 0x10,
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
        {
            ushort[] sdata = cast(ushort[])data;
            if((cast(size_t)sdata.ptr & 0x03) != 0)
            {
                // first two bytes are not aligned, do those specially
                *sdata.ptr = ((*sdata.ptr << 8) & 0xff00) |
                    ((*sdata.ptr >> 8) & 0x00ff);
                sdata = sdata[1..$];
            }
            // swap every 2 bytes
            // do majority using uint
            // TODO:  see if this can be optimized further, or if there are
            // better options for 64-bit.

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


/**
 * Input stream that supports utf
 *
 * This stream can be configured to use C or D-style streams.  The C-style
 * option is available in case you want to inter-mix C and D code
 * printing/reading.  Note that the D version is more optimized, has less
 * limitations, and is highly recommended.
 *
 * TextInput has full reference semantics.
 */
struct TextInput
{
    // the implementation struct, lives on the heap.
    private struct Impl
    {
        CStream input_c;
        DInput input_d;
        StreamWidth width;
        ByteOrder bo;
        bool discardBOM;

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

        // used to ensure the width is properly set without reading the stream
        // data.
        size_t determineWidth(const(ubyte)[] data, size_t start)
        {
            return width == StreamWidth.AUTO ? size_t.max : 0;
        }

        // used to ensure the width is properly set, and removes the BOM
        size_t readBOM(const(ubyte)[] data, size_t start)
        {

            switch(width)
            {
            case StreamWidth.AUTO:
                return size_t.max;

            case StreamWidth.UTF8:
                if(data.length < 3)
                    return size_t.max;
                if(data[0] == 0xef && data[1] == 0xbb && data[2] == 0xbf)
                    return 3;
                return 0;

            case StreamWidth.UTF16:
                if(data.length < 2)
                    return size_t.max;
                if(*cast(wchar*)data.ptr == 0xfeff)
                    return 2;
                return 0;

            case StreamWidth.UTF32:
                if(data.length < 4)
                    return size_t.max;
                if(*cast(dchar*)data.ptr == 0xfeff)
                    return 4;
                return 0;

            default:
                assert(0, "invalid stream width");
            }
        }
    }

    // the implementation pointer.
    private Impl* _impl;


    /**
     * Bind the TextInput to a given input stream.  A DInput will be used to
     * support the TextInput.
     */
    void bind(InputStream ins, StreamWidth width = StreamWidth.AUTO, ByteOrder bo = ByteOrder.Native)
    {
        bind(new DInput(ins), width, bo);
    }

    /**
     * Bind the TextInput to a buffered input stream.
     */
    void bind(DInput ins, StreamWidth width = StreamWidth.AUTO, ByteOrder bo = ByteOrder.Native)
    in
    {
        assert((width & ~StreamWidth.KEEP_BOM) == StreamWidth.AUTO ||
               (width & ~StreamWidth.KEEP_BOM) == StreamWidth.UTF8 ||
               (width & ~StreamWidth.KEEP_BOM) == StreamWidth.UTF16 ||
               (width & ~StreamWidth.KEEP_BOM) == StreamWidth.UTF32);
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
        _impl.input_c = null;
        _impl.width = cast(StreamWidth)(width & ~StreamWidth.KEEP_BOM);
        _impl.discardBOM = !(width & StreamWidth.KEEP_BOM);
    }

    /**
     * Bind the text input to a give C FILE object.  A CStream will be used to
     * support the TextInput.
     */
    void bind(FILE *fp)
    {
        bind(new CStream(fp));
    }

    /**
     * Bind the text input to a CStream.
     */
    void bind(CStream cstr)
    {
        if(!_impl)
            _impl = new Impl;
        _impl.input_c = cstr;
        _impl.input_d = null;
        _impl.width = StreamWidth.UTF8;
    }

    // used to check for the end of a line.
    private static size_t checkLineT(T)(const(ubyte)[] ubdata, size_t start, dchar terminator)
    {
        auto data = cast(const(T)[])ubdata[0..$ - (ubdata.length % T.sizeof)];
        start /= T.sizeof;
        bool done = false;
        foreach(size_t idx, dchar d; data[start..$])
        {
            if(done)
                return (start + idx) * T.sizeof;
            if(d == terminator)
                // need to go one more index.
                done = true;
        }
        return done ? data.length * T.sizeof: size_t.max;
    }

    // transcode a certain character width to another.  TODO: see if we really
    // need to use immutable, or if we can possibly reuse the buffer.
    private immutable(T)[] transcode(T, U)(const(ubyte)[] data)
    {
        return to!(immutable(T)[])(cast(const(U)[])data);
    }

    /**
     * Read a line of text from the stream.
     */
    const(T)[] readln(T = char)(dchar terminator = '\n') if(is(T == char) || is(T == wchar) || is(T == dchar))
    {
        if(_impl.input_d)
        {
            if(_impl.discardBOM)
            {
                _impl.input_d.readUntil(&_impl.readBOM);
                _impl.discardBOM = false;
            }
            // use the input_d function to read until a line terminator is
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
            const(ubyte)[] result = _impl.input_d.readUntil(&checkLine);
            if(_impl.width == T.sizeof)
            {
                return (cast(const(T)*)result.ptr)[0..result.length / T.sizeof];
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
                    return transcode!(T, char)(line);
            }
            else
                // no data, no need to do any allocation, etc.
                return (T[]).init;
        }
    }

    // input range supporting the CStream object
    private struct InputRangeC
    {
        // TODO: locking
        dchar _crt;
        FILE *_f;
        this(CStream cs)
        {
            _f = cs.cFile;
        }

        @property bool empty()
        {
            if (_crt == _crt.init)
            {
                _crt = fgetc(_f);
                if (_crt == -1)
                {
                    return true;
                }
                else
                {
                    enforce(ungetc(_crt, _f) == _crt);
                }
            }
            return false;
        }

        dchar front()
        {
            enforce(!empty);
            return _crt;
        }

        void popFront()
        {
            enforce(!empty);
            if (fgetc(_f) == -1)
            {
                enforce(feof(_f));
            }
            _crt = _crt.init;
        }
    }

    // input range supporting the DInput object, parameterized on character
    // type.
    private struct InputRangeD(CT)
    {
        private
        {
            DInput input;
            size_t curlen;
            dchar cur;
        }

        this(DInput di)
        {
            this.input = di;
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

        public void popFront()
        {
            input.skip(curlen);
            curlen = 0;
            input.readUntil(&parseDChar);
        }

        private size_t parseDChar(const(ubyte)[] data, size_t start)
        {
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
                        if(start == data.length)
                            // EOF, couldn't get a valid character.
                            return 0;
                        return size_t.max;
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
                            return 0;
                        case 3:
                            cur = ((data[0] & 0x0f) << 11) | 
                                ((data[1] & 0x3f) << 6) |
                                (data[2] & 0x3f);
                            return 0;
                        case 4:
                            cur = ((data[0] & 0x07) << 17) | 
                                ((data[1] & 0x3f) << 12) |
                                ((data[2] & 0x3f) << 6) |
                                (data[3] & 0x3f);
                            return 0;
                        default:
                            assert(0); // should never happen
                        }
                    }
                }
                else
                {
                    cur = data[0];
                    curlen = 1;
                    return 0;
                }
            }
            else static if(is(CT == wchar))
            {
                if(data.length < wchar.sizeof)
                {
                    if(data.length == start)
                        return 0;
                    else
                        return size_t.max;
                }
                auto wp = cast(const(wchar)*)data.ptr;
                cur = *wp;
                if(cur < 0xD800 || cur >= 0xE000)
                {
                    curlen = wchar.sizeof;
                    return 0;
                }
                else if(cur >= 0xDCFF)
                {
                    // second half of surrogate pair, invalid.
                    throw new Exception("invalid UTF sequence");
                }
                else if(data.length < wchar.sizeof * 2)
                {
                    // surrogate pair, but not enough space for the second
                    // wchar
                    if(start == data.length)
                        return 0;
                    else
                        return size_t.max;
                }
                else if(wp[1] < 0xDC00 || wp[1] >= 0xE000)
                {
                    throw new Exception("invalid UTF sequence");
                }
                else
                {
                    // combine the pairs
                    cur = (((cur & 0x3FF) << 10) | (wp[1] & 0x3FF)) + 0x10000;
                    curlen = wchar.sizeof * 2;
                    return 0;
                }
            }
            else // dchar
            {
                if(data.length < 4)
                {
                    if(data.length == start)
                        // do not consume a partial-character
                        return 0;
                    else
                        return size_t.max;
                }
                // got at least one dchar
                cur = *cast(const(dchar)*)data.ptr;
                curlen = 4;
                return 0;
            }
        }
    }

    /**
     * Formatted read.
     */
    public uint readf(Data...)(in char[] format, Data data)
    {
        if(_impl.input_d)
        {
            if(_impl.discardBOM)
            {
                _impl.input_d.readUntil(&_impl.readBOM);
                if(_impl.width == StreamWidth.AUTO)
                    // could not read anything
                    return 0;
            }
            else if(_impl.width == StreamWidth.AUTO)
            {
                _impl.input_d.readUntil(&_impl.determineWidth);
                if(_impl.width == StreamWidth.AUTO)
                    // could not read anything
                    return 0;
            }
            switch(_impl.width)
            {
            case StreamWidth.UTF8:
                {
                    auto ir = InputRangeD!char(_impl.input_d);
                    return formattedRead(ir, format, data);
                }
            case StreamWidth.UTF16:
                {
                    auto ir = InputRangeD!wchar(_impl.input_d);
                    return formattedRead(ir, format, data);
                }
            case StreamWidth.UTF32:
                {
                    auto ir = InputRangeD!dchar(_impl.input_d);
                    return formattedRead(ir, format, data);
                }
            default:
                assert(0); // should not get here
            }
        }
        else if(_impl.input_c)
        {
            writeln("using C input range");
            auto ir = InputRangeC(_impl.input_c);
            return formattedRead(ir, format, data);
        }
        else
            assert(0);
    }

    ByLine!Char byLine(Char = char)( Char terminator = '\n', KeepTerminator keepTerminator= KeepTerminator.no)
    {
        return ByLine!Char(this, keepTerminator, terminator);
    }
}

enum KeepTerminator : bool { no, yes }
struct ByLine(Char)
{
    private
    {
        TextInput input;
        const(Char)[] line;
        Char terminator;
        KeepTerminator keepTerminator;
    }

    this(TextInput f, KeepTerminator kt = KeepTerminator.no, Char terminator = '\n')
    {
        this.input = f;
        this.terminator = terminator;
        keepTerminator = kt;
        popFront();
    }

    @property bool empty()
    {
        return line is null;
    }

    void popFront()
    {
        line = input.readln(terminator);
        if(!line.length)
        {
            // signal that the range is now empty
            line = null;
        }
        else if(!keepTerminator)
        {
            while(line.length && line.back == terminator)
                line.popBack();
        }
    }

    @property const(Char)[] front()
    {
        return line;
    }
}

/**
 * Output stream that supports utf
 *
 * This stream can be configured to use C or D-style streams.  The C-style
 * option is available in case you want to inter-mix C and D code
 * printing/reading.  Note that the D version is more optimized, has less
 * limitations, and is highly recommended.
 *
 * TextOutput has full reference semantics.
 */
struct TextOutput
{
    private struct Impl
    {
        // D style buffered output
        DOutput output_d;
        // C style buffered output
        CStream output_c;

        // this is settable at runtime because the interface to a text stream
        // is independent of the character width being sent to it.  Otherwise,
        // it would not be possible to say, for example, change the output
        // width to wchar for stdou.
        ubyte charwidth;

        size_t encode(ubyte[] data)
        {
            // normalize, we can't encode anything that's a partial character.
            data = data[0..data.length - (data.length % charwidth)];
            __swapBytes(data, charwidth);
            return data.length;
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
     * Bind the TextOutput to an output stream object.  A DOutput buffered
     * stream will be created to support the TextInput.
     */
    void bind(OutputStream outs, StreamWidth width = StreamWidth.UTF8, ByteOrder bo = ByteOrder.Native)
    {
        bind(new DOutput(outs), width, bo);
    }

    /**
     * Bind the TextOutput to a buffered DOutput object.
     */
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

        if(auto f = cast(File)dbo.unbuffered)
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

        if(!_impl)
            _impl = new Impl;
        this._impl.output_d = dbo;
        this._impl.output_c = null;
        this._impl.charwidth = width;
    }

    /**
     * Bind the TextOutput to a FILE * C stream.  A CStream object will be
     * created to support the TextOutput.
     */
    void bind(FILE *outs)
    {
        bind(new CStream(outs));
    }

    /**
     * Bind the TextOutput to a CStream object.
     */
    void bind(CStream cstr)
    {
        if(!_impl)
            _impl = new Impl;
        this._impl.output_c = cstr;
        this._impl.output_d = null;
        this._impl.charwidth = StreamWidth.UTF8;
    }

    /**
     * Write data to the stream.
     */
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

    /**
     * Write a line of data to the stream.
     *
     * This is equivalent to write(args, '\n');
     */
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
        if(_impl.output_d)
            priv_write_stream!(C)(_impl.output_d, args);
        else
            priv_write_stream!(C)(_impl.output_c, args);
    }

    private void priv_write_stream(C, Output, S...)(Output op, S args)
    {
        //_output.begin();
        auto w = OutputRange!(C, Output)(op);

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
        if(_impl.output_d)
            priv_writef_stream!(C, doNewline)(_impl.output_d, args);
        else
            priv_writef_stream!(C, doNewline)(_impl.output_c, args);
    }

    private void priv_writef_stream(C, bool doNewline, Output, S...)(Output op, S args)
    {
        static assert(S.length > 0, errorMessage);
        static assert(isSomeString!(S[0]), errorMessage);
        //_output.begin();
        auto w = OutputRange!(C, Output)(op);
        std.format.formattedWrite(w, args);
        static if(doNewline)
        {
            w.put('\n');
        }
        //_output.end();
    }


    private struct OutputRange(CT, Output)
    {
        Output output;

        this(Output output)
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
                output.put((cast(const(ubyte)*) writeme.ptr)[0..writeme.length * CT.sizeof]);
            }
            else
            {
                version(inlineutf)
                {
                    static if(is(typeof(writeme[0]) : const(char)))
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
                    else static if(is(typeof(writeme[0]) : const(wchar)))
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
                else
                {
                    // convert to dchars, put each one out there.
                    foreach(dchar dc; writeme)
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
                        version(inlineutf)
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
                        else
                        {
                            char[4] buf = void;
                            auto b = std.utf.toUTF8(buf, c);
                            output.put((cast(ubyte*)b.ptr)[0..b.length]);
                        }
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
                    version(inlineutf)
                    {
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
                    else
                    {
                        auto b = std.utf.toUTF16(buf, c);
                        output.put((cast(ubyte*)b.ptr)[0..b.length * wchar.sizeof]);
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

    void flush()
    in
    {
        assert(_impl);
    }
    body
    {
        if(_impl.output_d)
            _impl.output_d.flush();
        else
            _impl.output_c.flush();
    }

    void close()
    in
    {
        assert(_impl);
    }
    body
    {
        if(_impl && _impl.output_d)
        {
            _impl.output_d.close();
            _impl.output_d = null;
        }
        else if(_impl && _impl.output_c)
        {
            _impl.output_c.close();
            _impl.output_c = null;
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
 * The mode string follows the conventions of File.open.  Note that binary is
 * ignored (all D streams are binary).
 *
 * Note that if mode indicates the stream is read and write (i.e. it contains a
 * '+'), a tuple(input, output) is returned.  TODO: we probably need a
 * full-fledged type for this.
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

    // set up the text streams
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

