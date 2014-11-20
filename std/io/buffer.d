module std.io.buffer;

/**
 * Array-based buffer
 */
struct ArrayBuffer
{
    static typeof(this) createDefault() {
        return typeof(this)(512, 8 * 1024);
    }

    static typeof(this) *allocateDefault() {
        return new typeof(this)(512, 8 * 1024);
    }

    this(size_t chunk, size_t initial) {
        import core.bitop : bsr;
        assert((chunk & (chunk - 1)) == 0 && chunk != 0);
        static assert(bsr(1) == 0);
        auto pageBits = bsr(chunk)+1;
        pageMask = (1<<pageBits)-1;
        //TODO: revisit with std.allocator
        buffer = new ubyte[initial<<pageBits];
        start = end = 0;
    }

    // get the valid data in the buffer
    @property auto window(){
        return buffer[start..end];
    }

    void discard(size_t toDiscard)
    {
        if(toDiscard > end-start)
            reset();
        else
            start += toDiscard;
    }

    // extends the buffer n bytes, returns the number of bytes that could be extended without reallocating.
    // This includes if the data has to be moved.
    //
    // Use 0 as parameter if you only want to determine how much you can request without allocating.
    // A negative value will shrink the "allocated" space down that much.
    size_t extend(ptrdiff_t n)
    {
        if(n > 0)
        {
            //TODO: tweak condition w.r.t. cost-benefit of compaction vs realloc
            //More TODO: if we are going to extend anyway, and that extend
            //will reallocate, we are copying data *twice*. Avoid that.
            //
            // currently, the code always compacts, even if it's inefficient. But only if n is non-zero
            if (start > 0) {
                // n + pageMask -> at least 1 page, no less then n
                copy(buffer[start .. end], buffer[0 .. end - start]);
                end -= start;
                start = 0;
            }
        }
        else if(cast(ptrdiff_t)start > cast(ptrdiff_t)end + n)
        {
            // erasing all data.
            reset();
            return buffer.length;
        }
        
        if(end + n > buffer.length)
        {
            // need to extend more data
            // rounded up to 2^^chunkBits
            //TODO: tweak grow rate formula
            auto oldLen = buffer.length;
            auto newLen = max(end + n, oldLen * 14 / 10);
            newLen = (newLen + pageMask) & ~pageMask; //round up to page
            buffer.length = newLen;
        }
        
        end += n;

        return buffer.length - (end - start);
    }

    size_t capacity() const
    {
        return buffer.length;
    }

    void reset()
    {
        // reset all buffer data.
        start = end = 0;
    }

private:
    ubyte[] buffer;
    size_t start; // start of data in buffer
    size_t end; // end of data in buffer
    size_t pageMask; //bit mask - used for fast rounding to multiple of page
}

unittest {
    import std.io.traits;
    static assert(isBuffer!(ArrayBuffer));
// TODO fill this out
}

// TODO circular buffer implementation (would be the proof that we got our API right)
