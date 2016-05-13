/**
 * Chain of buffer views that allows pipe-style passing
 * of data without copying
 */

module std.io.bufchain;
import std.traits;

/**
 * structure that implements a buffer chain.
 */
struct BufChain(BufImpl, Context, Procs...)
{
    pragma(msg, Procs.stringof);
    BufImpl bufImpl;
    static if(!is(Context == void))
        // used to pass information around the processors.
        Context context;
    // Note that positions go in descending order
    // first processor = pos[0]   .. bufImpl.length
    // all others      = pos[idx] .. pos[idx-1]
    //
    // Note that the data from pos[0] to bufImpl.length is considered UNUSED
    // data. It will not be preserved on a buffer extension. If one wishes to
    // preserve this data, start with a processor that passes all its data
    // immediately to the next processor.
    size_t[Procs.length] pos;
    Procs procs;

    /**
     * reset all positions, essentially clear the buffer. If a proc defines a
     * way to reset, we call it.
     */
    void reset()
    {
        pos[] = 0;
        foreach(ref p; procs)
        {
            static if(is(typeof(p.reset())))
                p.reset();
        }
    }

    /**
     * This gets a BufRef window for a specific processor. Used generally for
     * manually processed windows, but can be used to tweak certain windows.
     */
    auto getRef(uint idx)()
    {
        return BufRef!idx(&this);
    }
    
    // this structure is a reference that the buffer processor uses to
    // manipulate its window of the buffer. It should have no other access to the buffer.
    struct BufRef(uint idx)
    {
        static assert(idx < Procs.length);
        private BufChain *buf;
        auto window()
        {
            static if(idx == 0)
            {
                return buf.bufImpl.window[buf.pos[0] .. $];
            }
            else
            {
                return buf.bufImpl.window[buf.pos[idx] .. buf.pos[idx-1]];
            }
        }

        // release numBytes to the next processor. This relinqueshes control
        // over that data, this processor can no longer use it, and it should
        // adjust any internal markers to account for that data being gone.
        void release(size_t numBytes)
        {
            static if(idx)
                assert(buf.pos[idx] + numBytes <= buf.pos[idx-1]);
            else
                assert(buf.pos[idx] + numBytes <= buf.bufImpl.window.length);
            buf.pos[idx] += numBytes;
        }

        // request more free space from the precedents. If the buffer
        // processor is index 0, then the buffer chain may request more space
        // from the buffer. The added bytes of free space is returned. If no
        // free space can be given, 0 is returned.
        size_t request(size_t minNewSpace, size_t maxNewSpace = 0)
        {
            import std.algorithm.comparison: min;
            static if(idx == 0)
            {
                // we are going to flush the unused space at the back
                immutable toDiscard = buf.pos[$-1];

                // ask the buffer for more space
                size_t result = buf.bufImpl.extend(toDiscard, buf.pos[0], minNewSpace, maxNewSpace);

                if(toDiscard > 0)
                {
                    foreach(ref b; buf.pos)
                    {
                        // each pos needs to be adjusted to account for the discarded bytes
                        b -= toDiscard;
                    }
                }

                return result;
            }
            else static if(idx == 1)
            {
                // second buffer processor, since the fist buffer processor has
                // no valid data (by definition), we can steal as much space as
                // we want without asking.
                immutable unusedBytes = buf.bufImpl.window.length - buf.pos[0];
                size_t result = void;
                if(unusedBytes > minNewSpace)
                {
                    result = min(maxNewSpace, unusedBytes);
                }
                else
                {
                    result = min(maxNewSpace, buf.getRef!(0).request(minNewSpace - unusedBytes, maxNewSpace - unusedBytes) + unusedBytes);
                }
                buf.pos[0] += result;
                return result;
            }
            else
            {
                if(buf.pos[idx-1] == buf.pos[idx-2])
                {
                    // the predecessor processor is not holding onto any data,
                    // trivial to increase free space from further precedent
                    auto result = buf.getRef!(idx-1).request(minNewSpace, maxNewSpace);
                    buf.pos[idx-1] += result;
                    return result;
                }
                else
                {
                    // check to see if the upstream buffer processor supports free space requests
                    static if(is(typeof(buf.procs[idx-1].request(buf.getRef!(idx-1), minNewSpace, maxNewSpace))))
                    {
                        auto result = buf.procs[idx-1].request(buf.getRef!(idx - 1), minNewSpace, maxNewSpace);
                        return result;
                    }
                    else
                    {
                        // no support for getting free space from precedents
                        return 0;
                    }
                }
            }
        }

        static if(idx != 0)
        {
            auto upstreamProcessor()
            {
                return buf.procs[idx-1];
            }
        }
        static if(idx + 1 != procs.length)
        {
            auto downstreamProcessor()
            {
                return buf.procs[idx+1];
            }
        }

        static if(!is(Context == void))
        {
            ref context()
            {
                return buf.context;
            }
        }
    }

    // get an adapter that provides access to the processor, buffer reference, and
    // provides a specialized mechanism to call functions that take the buffer reference as
    // the first parameter.
    auto getProc(uint idx)()
    {
        static struct Result
        {
            BufRef!idx bRef;
            ref processor() { return bRef.buf.procs[idx]; }

            // this should forward any call to processor with bref as the first
            // parameter
            template opDispatch(string s) {
                template opDispatch(E...) {
                    auto ref opDispatch(T...)(T args)
                    {
                        static if(E.length){
                            static if(is(typeof(mixin("processor()." ~ s ~ "!E(bRef, args)"))))
                                return mixin("processor()." ~ s ~ "!E(bRef, args)");
                            else static if(T.length == 0)
                                return mixin("processor()." ~ s ~ "!E");
                            else
                                return mixin("processor()." ~ s ~ "!E(args)");
                        }
                        else
                        {
                            static if(is(typeof(mixin("processor()." ~ s ~ "(bRef, args)"))))
                                return mixin("processor()." ~ s ~ "(bRef, args)");
                            else static if(T.length == 0)
                                return mixin("processor()." ~ s);
                            else
                                return mixin("processor()." ~ s ~ "(args)");
                        }
                    }
                }
            }
        }
        return Result(getRef!idx());
    }
    
    // return nonzero if any bytes moved within or out of specified subchain
    // (i.e. progress is made).
    int process(uint start = 0, uint end = Procs.length)() if(start <= end)
    {
        int changes = 0;
        size_t origPos = void;
        foreach(i, ref p; procs[start .. end])
        {
            static if(__traits(hasMember, typeof(p), "processBuf"))
            {
                static if(i + 1 == pos.length)
                {
                    origPos = pos[i];
                    p.processBuf(getRef!i);
                    changes += (origPos != pos[i]);
                }
                else
                {
                    origPos = pos[i] - pos[$-1];
                    p.processBuf(getRef!i);
                    changes += (origPos != pos[i] - pos[$-1]);
                }
            }
            else
                break;
        }
        return changes;
    }
    
    // get more data from the precedents. Returns non-zero if
    // data moved at all (may not be any new data available, even if
    // data has moved, you may try again, but a return of 0 should mean
    // that no more data will be given).
    int underflow(uint idx)()
    {
        // first, process all elements that could possibly give more data
        // to the underlying buffer, then flush, then process all elements
        // in front of this element.
        return process!(idx + 1)() + process!(0, idx)();
    }

}


// specialized buffer chain processor that adapts an output stream to a buffer
// chain processor.
struct OutputAdapter(OutputStream, size_t alignment = 1)
{
    // alignment must be a power of 2.
    static assert(alignment && (alignment & (alignment - 1)) == 0);
    
    private OutputStream output;
    static if(alignment > 1)
        private size_t held;
    else
        private enum held = 0;
    void processBuf(BufRef)(BufRef buffer)
    {
        // need to write all data to the output stream
        auto bytesWritten = output.write(buffer.window[held..$]) + held;
        
        // we can't violate alignment, so hold back from releasing some bytes
        // to keep alignment correct
        static if(alignment > 1)
            held = (bytesWritten % alignment);
        buffer.release(bytesWritten - held);
    }
    
    this(OutputStream val)
    {
        output = val;
    }
    
    OutputStream stream()
    {
        return output;
    }
}

// specialized buffer chain processor that adapts an input stream to a buffer
// chain processor.
struct InputAdapter(InputStream, size_t OptReadSize = 4096 * 10)
{
    private InputStream input;
    void processBuf(BufRef)(BufRef buffer)
    {
        // Try and ensure we get an optimal read size
        auto curlen = buffer.window.length;
        if(curlen < OptReadSize)
            buffer.request(OptReadSize - curlen);

        // Really simple. Read all the data we can. Send it along
        auto bytesRead = input.read(buffer.window);
        buffer.release(bytesRead);
    }
    
    this(InputStream val)
    {
        input = val;
    }
    
    InputStream stream()
    {
        return input;
    }

    size_t request(BufRef)(BufRef buffer, size_t minNewData, size_t maxNewData)
    {
        // since we don't care at all about data we own, just forward along
        auto curLength = buffer.window.length;
        if(curLength < minNewData)
            curLength += buffer.request(minNewData - curLength);
        if(curLength > maxNewData)
            curLength = maxNewData;
        buffer.release(curLength);
        return curLength;
    }
}
