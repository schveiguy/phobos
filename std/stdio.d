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
import std.string;
import std.format;

version(Posix)
{
    import core.stdc.stdlib;
    import core.sys.posix.unistd;
    import core.sys.posix.fcntl;
    extern(C) ssize_t getdelim (char**, size_t*, int, FILE*);
}

public import core.stdc.stdio;
import core.stdc.string;

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
     */
    const(ubyte)[] readln(ubyte lineterm = '\n');

    /**
     * Close the stream.  This releases any resources from the object.
     */
    void close();

    /**
     * Begin a read
     */
    void begin();

    /**
     * End a read
     */
    void end();
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

    /**
     * Begin a write.  This can be used to optimize writes to the stream, such
     * as avoiding flushing until an entire write is done, or to take a lock on
     * the stream.
     *
     * The implementation may do nothing for this function.
     */
    void begin();

    /**
     * End a write.  This can be used to optimize writes to the stream, such
     * as avoiding auto-flushing until an entire write is done, or to take a
     * lock on the stream.
     *
     * The implementation may do nothing for this function.
     */
    void end();

    /**
     * Flush the written data in the buffer into the underlying output stream.
     */
    void flush();

    /**
     * Close the stream.  This releases any resources from the object.
     */
    void close();
}

class DStream : InputStream, OutputStream
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
    static DStream open(const char[] name, const char[] mode = "rb")
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
        auto result = new DStream(fd);

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
    
    final const(ubyte)[] readln(ubyte lineterm = '\n')
    {
        size_t _checkDelim(const(ubyte)[] data, size_t start)
        {
            auto ptr = data.ptr + start;
            auto end = data.ptr + data.length;
            for(;ptr < end; ++ptr)
            {
                if(*ptr == delim)
                    break;
            }
            return ptr - data.ptr + 1;
        }

        return readUntil(&_checkDelim);
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

    override void begin()
    {
        // no specialized code needed.
    }

    override void end()
    {
        // no specialized code needed.
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
        if(_flushCheck && writepos - _startofwrite > 0)
        {
            auto fcheck = _flushCheck(buffer[_startofwrite..writepos]);
            if(fcheck >= 0)
            {
                // need to flush some data
                auto endpos = _startofwrite + fcheck;
                ensureWrite(buffer[0..endpos]);

                // now, we need to move the data to the front of the buffer
                // this is the only place we have to do this.
                if(writepos != endpos)
                    memmove(buffer.ptr, buffer.ptr + endpos, writepos - endpos);
                writepos -= endpos;
            }
        }
        _startofwrite = 0;
    }

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
            // minimize the calls to output.write.
            if(writepos && minwrite <= buffer.length)
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

class CStream : BufferedInput, BufferedOutput
{
    private
    {
        FILE *source;
        char *_buf; // C malloc'd buffer used to support getDelim
        size_t _bufsize; // size of buffer
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
    }

    void begin()
    {
        FLOCK(source);
    }

    void end()
    {
        FUNLOCK(source);
    }

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
        size_t result = fread(data.ptr, ubyte.sizeof, data.length, source);
        if(result < data.length)
        {
            // could be error or eof, check error
            if(ferror(source))
                throw new Exception("Error reading");
        }
        return result;
    }

    const(ubyte)[] readln(ubyte lineterm = '\n')
    {
        auto result = .getdelim(&_buf, &_bufsize, delim, source);
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
        auto result = fwrite(data.ptr, ubyte.sizeof, data.length, source);
        if(result < data.length)
            throw new Exception("Error writing data");
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
struct FInput
{
    private BufferedInput input;

    this(BufferedInput input)
    {
        this.input = input;
    }
}

// formatted output stream
struct FOutput
{
    // public so it can be reassigned.
    public BufferedOutput output;

    // this is settable at runtime because the interface to a text stream is
    // independent of the data being sent to it.
    private ubyte _charwidth;

    this(BufferedOutput output, size_t charwidth)
    in
    {
        assert(charwidth == 1 || charwidth == 2 || charwidth == 4);
    }
    body
    {
        this.output = output;
        this._charwidth = charwidth;
    }

    void write(S...)(S args)
    {
        switch(_charwidth)
        {
        case 1:
            priv_write!(char, false)(args);
            break;
        case 2:
            priv_write!(wchar, false)(args);
            break;
        case 4:
            priv_write!(dchar, false)(args);
            break;
        default:
            assert(0);
        }
    }

    private void priv_write(C, bool doFlush, S...)(S args)
    {
        output.begin();
        w = OutputRange!C(output);

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
        static if(doFlush)
            output.flush();
        output.end();
    }

    void writeln(S...)(S args)
    {
        switch(_charwidth)
        {
        case 1:
            priv_write!(char, true)(args, '\n');
            break;
        case 2:
            priv_write!(wchar, true)(args, '\n');
            break;
        case 4:
            priv_write!(dchar, true)(args, '\n');
            break;
        default:
            assert(0);
        }
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

    private void priv_writef(C, bool doNewline, S...)(S args)
    {
        static assert(S.length > 0, errorMessage);
        static assert(isSomeString!(S[0]), errorMessage);
        output.begin();
        OutputRange!C w;
        std.format.formattedWrite(w, args);
        static if(doNewline)
        {
            w.put('\n');
            output.flush();
        }
        output.end();
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


    private struct _outputrange(CT)
    {
        OutputStream output;

        this(OutputStream output)
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
            static if(C.sizeof == CT.sizeof)
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
                    auto dchar dc = c;
                    assert(isValidDchar(dc));
                    output.put(cast(ubyte[])(&dc)[0..1]);
                }
                else
                    static assert(0, "invalid types used for output stream, " ~ CT.stringof ~ ", " ~ C.stringof);
            }
        }
    }
}

auto openFile(string mode = "r")(string fname)
{
    static if(mode == "r")
        return new DBufferedInput(DStream.open(fname, mode));
    else
        static assert(0, "mode not supported for openFile: " ~ mode);
}
