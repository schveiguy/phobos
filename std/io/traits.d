module std.io.traits;
import std.range;
/**
   io traits

   There are several layers of i/o types. At the lowest level, we have a stream. A stream is simply an abstraction of a mechanism to read and write data from an I/O source or sink. Obviously we have two types of streams, one for each direction. Two fundamental streams are provided: A NullStream provides input and output functions that act as if the sink or source were at EOF. An InfiniteStream provides input and output functions that act as if the sink or source always read or wrote the requested data. These can be used to cap ends of a stream chain so that we can make read only or write only streams, or buffers that have no sink or source, without having to implement special cases for these. Note that these streams only work in terms of ubyte slices. No other data types are supported. The stream can optionally support reading from/writing to a range of buffers.

   Orthogonally, at the lowest level we have a Buffer. A buffer simply provides space that can be written/read or extended. A Buffer does not necessarily need to provide contiguous space, but must provide random access to that space. The buffer's primitives allow it to extend for more space at the end, and discard no-longer needed space from the beginning. If the data must be moved, the buffer handles the moving. Buffers deal only in arrays of ubyte. If a buffer does not provide a ubyte[] window, it must also provide an accessor that yields a range of ubyte[], that has a length.

   On top of the buffer and stream types, we have a StreamWindow. A StreamWindow abstracts input, output, and a buffer into one representation. Generally a StreamWindow is constructed using input output and buffer types, but could be specialized on any of those. Data is read by the StreamWindow from the input stream, and placed into the buffer. Data that is ready for output is also written by the StreamWindow from the buffer into the output stream. StreamWindows may present their window as type-specific ranges of data (e.g. char[]). Some StreamWindows may provide different types of slices (e.g. use template function to get slices of char[], wchar[], or dchar[] depending on an encoding).
   
   On top of the StreamWindow, one has access to a BufferRange. A BufferRange adds the notion of a specific position to a StreamWindow. A BufferRange is an input range, which provides sequential access to the underlying buffer. A BufferRange is linked to the underlying StreamWindow, such that flushes of data in the StreamWindow do not alter the BufferRange's position. A BufferRange can only move forward, and is not guaranteed to be saveable a la forward ranges, but may support the forward range idiom. It may provide write access to the underlying window, but only if the window allows it.

   On top of BufferRanges, is where one should implement high-level ranges that give structure to the data. std.io provides several possible ranges out of the box.
 */

/**
 * isBuffer test
 */
enum isBuffer(Buffer) = __traits(compiles, (ref Buffer b){
    import std.range;
    auto r = b.window;
    alias R = typeof(r);
    static assert(is(R == ubyte[]));
    buf.discard(size_t.max);
    assert(buf.extend(ptrdiff_t.min));
    assert(buf.capacity);
    buf.reset();
});

/**
 * A Multi Buffer is a buffer that provides a range of ubyte[]. This is useful
 * for avoiding copying data when flushing the beginning of the buffer.
 */
enum isMultiBufferParameter(R) = isForwardRange!R && is(ElementType!R == ubyte[]) && hasLength!R;
enum isOutputMultiBufferParameter(R) = isForwardRange!R && is(ElementType!R : const(ubyte)[]) && hasLength!R;

/**
 * A scatter buffer provides its window as a multibuffer. Such a buffer can be
 * output to a stream either by inputting/outputting each individual ubyte[],
 * or if supported by reading/writing the ubyte[] slices to the stream at once
 * with supported functions (e.g. writev/readv)
 */
enum isScatterBuffer(Buffer) = __traits(compiles, (ref Buffer b){
    import std.range;
    auto r = b.window;
    static assert(isMultiBufferParameter!(typeof(R)));
});


enum isStreamWindow(T) = __traits(compiles, (ref T t){
    import std.range;
    t.load(size_t.max, size_t.max);
    t.load(size_t.max);
    t.close();
    auto w = t.window;
    // R may not be ubyte range.
    alias R = typeof(w);
    static assert(isForwardRange!R);
    w.reset();
});

/**
    Test if $(D T) follows Buffer concept. In particular the following code
    must compile for any $(D buf) of compatible type $(D T):
    ---
    static assert(isInputRange!T);
    static assert(is(ElementEncodingType!T == E));
    if(!buf.empty) {
        assert(buf.window); // get window of visible data in buffer
        static assert(isSliceable!(typeof(buf.window)));
        assert(buf.skip(5)); // skip ahead N bytes.
        assert(buf.extend(size_t.max));
        assert(buf.extend());
    }
    ---
*/
enum isBufferRange(T) = __traits(compiles, (T buf){
    import std.range;
    static assert(isInputRange!T);
    if(!buf.empty) {
        assert(buf.window);
        static assert(isSliceable!(typeof(buf.window)));
        static assert(is(typeof(buf.skip(5)) == size_t));
        static assert(is(typeof(buf.extend(size_t.max)) == size_t));
        static assert(is(typeof(buf.extend()) == size_t));
    }
});

/**
    A mock implementation of Buffer concept.
    A type useful for compile-time instantiation checking.
*/
struct NullBufferRange{
    ///InputRange troika.
    @property ubyte front(){ return 0; }
    ///ditto
    @property bool empty(){ return true; }
    ///ditto
    void popFront(){ assert(0); }
    /**
        Ensure the current buffer has n bytes in it. This is allowed to fail, in which
        case the buffer will have less than n bytes in it. It returns the number of bytes
        added to the current window. If the return value is 0, then the source has
        been exhausted.
    */
    @property size_t extend(size_t n = ~0){ return 0; }
    /**
        Take a slice starting from $(D n) bytes behind to the current position.
        On success the size of slcie is strictly equal $(D n)
        otherwise an empty slice is returned.
    */
    /// Skip ahead n bytes.
    size_t skip(size_t){ return 0; }
    /// get a window of all the elements this range has buffered
    ubyte[] window(){ return null; }
}

/**
    Test if can retain $(D Buffer)'s data slices directly, without taking a copy.
    The buffer type has to provide a slice as random access range
    having element type of $(D immutable(ubyte)).
TODO: not sure if we need this.
*/
enum isZeroCopy(Buffer)  = isBufferRange!Buffer && __traits(compiles, (Buffer buf){
    import std.range;
    //slice may as well take only L-values
    alias SliceType = typeof(buf.window);
    static assert(isSliceable!SliceType);
    // TODO, I don't think this is right
    static assert(is(ElementType!SliceType == immutable));
});

/**
    Tests if $(D Stream) follows the InputStream concept.
    In particular the following code must compiler for any Stream $(D s):
    ---
    (ref Stream s){
        ubyte[] buf;
        size_t len = s.read(buf);
        assert(s.eof);
        s.close();
    }
    ---
    $(D Stream) itself shall not have elaborate destructor and postblit
    and make no attempt at managing the liftime of the underlying resource.
    The ownership and deterministic release of resource
    are handled by a buffer range(s) working on this stream.

    In particular this allows class-based polymorphic $(D Stream) implementations
    to work w/o relying on nondeterministic GC finalization.

    See also $(DPREF2 _buffer, traits, NullStream).
*/
enum isInputStream(Stream) = __traits(compiles, (ref Stream s){
    ubyte[] buf;
    size_t len = s.read(buf);
    s.close();
});

enum isMultiInputStream(Stream) = isInputStream!Stream && __traits(compiles, (ref Stream s){
    // TODO: we really should define a custom range here, as we are testing an IFTI function.
    ubyte[][] buf;
    size_t len = s.read(buf);
});

enum isOutputStream(Stream) = __traits(compiles, (ref Stream s){
    const(ubyte)[] buf;
    size_t len = s.write(buf);
    s.close();
});

enum isMultiOutputStream(Stream) = isOutputStream!Stream && __traits(compiles, (ref Stream s){
    // TODO: we really should define a custom range here, as we are testing an IFTI function.
    const(ubyte)[][] buf;
    size_t len = s.write(buf);
    s.close();
});




///A do nothing implementation of InputStream and OutputStream concept.
struct NullStream
{
    /**
        Read some bytes to dest and return the amount acutally read.
        Upper limit is dest.length bytes.
    */
    size_t read(R)(R r) if(isMultiBufferParameter!R || is(R == ubyte[])) { return 0; }
    size_t write(R)(R r) if(isOutputMultiBufferParameter!R || is(R : const(ubyte)[])){ return 0; }
    void close(){}
}

// basically returns that it always filled the requested data. Used for an input-only or
// output-only stream

struct InfiniteStream
{
    size_t read(ubyte[] dest) {return dest.length;}
    size_t read(R)(R dest) if(isMultiBufferParameter!R)
    {
        size_t result = 0;
        foreach(x; dest)
            result += x.length;
        return x;
    }

    size_t write(const(ubyte)[] src) {return src.length;}
    size_t write(R)(R r) if (isOutputMultiBufferParameter!R)
    {
        // need to count all data to be "written".
        size_t result = 0;
        foreach(x; r)
        {
            result += x.length;
        }
        return result;
    }

    void close(){}
}

// test to see if a type is a buffered stream. It uses a buffer
// that is backed by a stream.

unittest
{
    import std.typetuple;
    static assert(isBufferRange!NullBufferRange);
    static assert(allSatisfy(isMultiInputStream, NullStream, InfiniteStream);
    static assert(allSatisfy(isMultiOutputStream, NullStream, InfiniteStream);
}
