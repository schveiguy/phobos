module std.container.dlist;

import std.range.constraints;
import std.traits;

public import std.container.util;

/+
A DList Node without payload. Used to handle the sentinel node (henceforth "sentinode").

Also used for parts of the code that don't depend on the payload type.
 +/
private struct BaseNode
{
    private BaseNode* _prev = null;
    private BaseNode* _next = null;

    /+
    Gets the payload associated with this node.
    This is trusted because all nodes are associated with a payload, even
    the sentinel node.
    It is also not possible to mix Nodes in DLists of different types.
    This function is implemented as a member function here, as UFCS does not
    work with pointers.
    +/
    ref inout(T) getPayload(T)() inout @trusted
    {
        return (cast(inout(DList!T.PayNode)*)&this)._payload;
    }

    // Helper: Given nodes p and n, connects them.
    static void connect(BaseNode* p, BaseNode* n) @safe nothrow pure
    {
        p._next = n;
        n._prev = p;
    }
}

/+
The base DList Range. Contains Range primitives that don't depend on payload type.
 +/
private struct DRange
{
    unittest
    {
        static assert(isBidirectionalRange!DRange);
        static assert(is(ElementType!DRange == BaseNode*));       
    }
 
nothrow @safe pure:
    private BaseNode* _first;
    private BaseNode* _last;

    private this(BaseNode* first, BaseNode* last)
    {
        assert((first is null) == (last is null), "Dlist.Range.this: Invalid arguments");
        _first = first;
        _last = last;
    }
    private this(BaseNode* n)
    {
        this(n, n);
    }

    @property
    bool empty() const
    {
        assert((_first is null) == (_last is null), "DList.Range: Invalidated state");
        return !_first;
    }

    @property BaseNode* front()
    {
        assert(!empty, "DList.Range.front: Range is empty");
        return _first;
    }

    void popFront()
    {
        assert(!empty, "DList.Range.popFront: Range is empty");
        if (_first is _last)
        {
            _first = _last = null;
        }
        else
        {
            assert(_first._next && _first is _first._next._prev, "DList.Range: Invalidated state");
            _first = _first._next;
        }
    }

    @property BaseNode* back()
    {
        assert(!empty, "DList.Range.front: Range is empty");
        return _last;
    }

    void popBack()
    {
        assert(!empty, "DList.Range.popBack: Range is empty");
        if (_first is _last)
        {
            _first = _last = null;
        }
        else
        {
            assert(_last._prev && _last is _last._prev._next, "DList.Range: Invalidated state");
            _last = _last._prev;
        }
    }

    /// Forward range primitive.
    @property DRange save() { return this; }
}

/**
Implements a doubly-linked list.

$(D DList) uses reference semantics.
 */
struct DList(T)
{
    import std.range : Take;

    /*
    A Node with a Payload. A PayNode.
     */
    struct PayNode
    {
        BaseNode _base;
        alias _base this;
    
        T _payload = T.init;
    
        inout(BaseNode)* asBaseNode() inout @trusted
        {
            return &_base;
        }
    }

    //The sentinel node
    private BaseNode* _root;

  private
  {
    //Construct as new PayNode, and returns it as a BaseNode.
    static BaseNode* createNode()(ref T arg, BaseNode* prev = null, BaseNode* next = null)
    {
        return (new PayNode(BaseNode(prev, next), arg)).asBaseNode();
    }

    void initialize() nothrow @safe pure
    {
        if (_root) return;
        //Note: We allocate a PayNode for safety reasons.
        _root = (new PayNode()).asBaseNode();
        _root._next = _root._prev = _root;
    }
    ref inout(BaseNode*) _first() @property @safe nothrow pure inout
    {
        assert(_root);
        return _root._next;
    }
    ref inout(BaseNode*) _last() @property @safe nothrow pure inout
    {
        assert(_root);
        return _root._prev;
    }
  } //end private

/**
Constructor taking a number of nodes
     */
    this(U)(U[] values...) if (isImplicitlyConvertible!(U, T))
    {
        insertBack(values);
    }

/**
Constructor taking an input range
     */
    this(Stuff)(Stuff stuff)
    if (isInputRange!Stuff && isImplicitlyConvertible!(ElementType!Stuff, T))
    {
        insertBack(stuff);
    }

/**
Comparison for equality.

Complexity: $(BIGOH min(n, n1)) where $(D n1) is the number of
elements in $(D rhs).
     */
    bool opEquals()(ref const DList rhs) const
    if (is(typeof(front == front)))
    {
        const lhs = this;
        const lroot = lhs._root;
        const rroot = rhs._root;

        if (lroot is rroot) return true;
        if (lroot is null) return rroot is rroot._next;
        if (rroot is null) return lroot is lroot._next;

        const(BaseNode)* pl = lhs._first;
        const(BaseNode)* pr = rhs._first;
        while (true)
        {
            if (pl is lroot) return pr is rroot;
            if (pr is rroot) return false;

            // !== because of NaN
            if (!(pl.getPayload!T() == pr.getPayload!T())) return false;

            pl = pl._next;
            pr = pr._next;
        }
    }

    /**
    Defines the container's primary range, which embodies a bidirectional range.
     */
    struct Range
    {
        static assert(isBidirectionalRange!Range);

        DRange _base;
        alias _base this;

        private this(BaseNode* first, BaseNode* last)
        {
            _base = DRange(first, last);
        }
        private this(BaseNode* n)
        {
            this(n, n);
        }

        @property ref T front()
        {
            return _base.front.getPayload!T();
        }

        @property ref T back()
        {
            return _base.back.getPayload!T();
        }

        //Note: shadows base DRange.save.
        //Necessary for static covariance.
        @property Range save() { return this; }
    }

/**
Property returning $(D true) if and only if the container has no
elements.

Complexity: $(BIGOH 1)
     */
    bool empty() @property const nothrow
    {
        return _root is null || _root is _first;
    }

/**
Removes all contents from the $(D DList).

Postcondition: $(D empty)

Complexity: $(BIGOH 1)
     */
    void clear()
    {
        //remove actual elements.
        remove(this[]);
    }

/**
Duplicates the container. The elements themselves are not transitively
duplicated.

Complexity: $(BIGOH n).
     */
    @property DList dup()
    {
        return DList(this[]);
    }

/**
Returns a range that iterates over all elements of the container, in
forward order.

Complexity: $(BIGOH 1)
     */
    Range opSlice()
    {
        if (empty)
            return Range(null, null);
        else
            return Range(_first, _last);
    }

/**
Forward to $(D opSlice().front).

Complexity: $(BIGOH 1)
     */
    @property ref inout(T) front() inout
    {
        assert(!empty, "DList.front: List is empty");
        return _first.getPayload!T();
    }

/**
Forward to $(D opSlice().back).

Complexity: $(BIGOH 1)
     */
    @property ref inout(T) back() inout
    {
        assert(!empty, "DList.back: List is empty");
        return _last.getPayload!T();
    }

/+ ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ +/
/+                        BEGIN CONCAT FUNCTIONS HERE                         +/
/+ ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ +/

/**
Returns a new $(D DList) that's the concatenation of $(D this) and its
argument $(D rhs).
     */
    DList opBinary(string op, Stuff)(Stuff rhs)
    if (op == "~" && is(typeof(insertBack(rhs))))
    {
        auto ret = this.dup;
        ret.insertBack(rhs);
        return ret;
    }

/**
Returns a new $(D DList) that's the concatenation of the argument $(D lhs)
and $(D this).
     */
    DList opBinaryRight(string op, Stuff)(Stuff lhs)
    if (op == "~" && is(typeof(insertFront(lhs))))
    {
        auto ret = this.dup;
        ret.insertFront(lhs);
        return ret;
    }

/**
Appends the contents of the argument $(D rhs) into $(D this).
     */
    DList opOpAssign(string op, Stuff)(Stuff rhs)
    if (op == "~" && is(typeof(insertBack(rhs))))
    {
        insertBack(rhs);
        return this;
    }

/// ditto
    deprecated("Please, use `dlist ~= dlist[];` instead.")
    DList opOpAssign(string op)(DList rhs)
    if (op == "~")
    {
        return this ~= rhs[];
    }

/+ ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ +/
/+                        BEGIN INSERT FUNCTIONS HERE                         +/
/+ ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ +/

/**
Inserts $(D stuff) to the front/back of the container. $(D stuff) can be a
value convertible to $(D T) or a range of objects convertible to $(D
T). The stable version behaves the same, but guarantees that ranges
iterating over the container are never invalidated.

Returns: The number of elements inserted

Complexity: $(BIGOH log(n))
     */
    size_t insertFront(Stuff)(Stuff stuff)
    {
        initialize();
        return insertAfterNode(_root, stuff);
    }

    /// ditto
    size_t insertBack(Stuff)(Stuff stuff)
    {
        initialize();
        return insertBeforeNode(_root, stuff);
    }

    /// ditto
    alias insert = insertBack;

    /// ditto
    alias stableInsert = insert;

    /// ditto
    alias stableInsertFront = insertFront;

    /// ditto
    alias stableInsertBack = insertBack;

/**
Inserts $(D stuff) after range $(D r), which must be a non-empty range
previously extracted from this container.

$(D stuff) can be a value convertible to $(D T) or a range of objects
convertible to $(D T). The stable version behaves the same, but
guarantees that ranges iterating over the container are never
invalidated.

Returns: The number of values inserted.

Complexity: $(BIGOH k + m), where $(D k) is the number of elements in
$(D r) and $(D m) is the length of $(D stuff).
     */
    size_t insertBefore(Stuff)(Range r, Stuff stuff)
    {
        if (r._first)
            return insertBeforeNode(r._first, stuff);
        else
        {
            initialize();
            return insertAfterNode(_root, stuff);
        }
    }

    /// ditto
    alias stableInsertBefore = insertBefore;

    /// ditto
    size_t insertAfter(Stuff)(Range r, Stuff stuff)
    {
        if (r._last)
            return insertAfterNode(r._last, stuff);
        else
        {
            initialize();
            return insertBeforeNode(_root, stuff);
        }
    }

    /// ditto
    alias stableInsertAfter = insertAfter;

/+ ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ +/
/+                        BEGIN REMOVE FUNCTIONS HERE                         +/
/+ ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ +/

/**
Picks one value in an unspecified position in the container, removes
it from the container, and returns it. The stable version behaves the same,
but guarantees that ranges iterating over the container are never invalidated.

Precondition: $(D !empty)

Returns: The element removed.

Complexity: $(BIGOH 1).
     */
    T removeAny()
    {
        import std.algorithm : move;

        assert(!empty, "DList.removeAny: List is empty");
        auto result = move(back);
        removeBack();
        return result;
    }
    /// ditto
    alias stableRemoveAny = removeAny;

/**
Removes the value at the front/back of the container. The stable version
behaves the same, but guarantees that ranges iterating over the
container are never invalidated.

Precondition: $(D !empty)

Complexity: $(BIGOH 1).
     */
    void removeFront()
    {
        assert(!empty, "DList.removeFront: List is empty");
        assert(_root is _first._prev, "DList: Inconsistent state");
        BaseNode.connect(_root, _first._next);
    }

    /// ditto
    alias stableRemoveFront = removeFront;

    /// ditto
    void removeBack()
    {
        assert(!empty, "DList.removeBack: List is empty");
        assert(_last._next is _root, "DList: Inconsistent state");
        BaseNode.connect(_last._prev, _root);
    }

    /// ditto
    alias stableRemoveBack = removeBack;

/**
Removes $(D howMany) values at the front or back of the
container. Unlike the unparameterized versions above, these functions
do not throw if they could not remove $(D howMany) elements. Instead,
if $(D howMany > n), all elements are removed. The returned value is
the effective number of elements removed. The stable version behaves
the same, but guarantees that ranges iterating over the container are
never invalidated.

Returns: The number of elements removed

Complexity: $(BIGOH howMany).
     */
    size_t removeFront(size_t howMany)
    {
        if (!_root) return 0;
        size_t result;
        auto p = _first;
        while (p !is _root && result < howMany)
        {
            p = p._next;
            ++result;
        }
        BaseNode.connect(_root, p);
        return result;
    }

    /// ditto
    alias stableRemoveFront = removeFront;

    /// ditto
    size_t removeBack(size_t howMany)
    {
        if (!_root) return 0;
        size_t result;
        auto p = _last;
        while (p !is _root && result < howMany)
        {
            p = p._prev;
            ++result;
        }
        BaseNode.connect(p, _root);
        return result;
    }

    /// ditto
    alias stableRemoveBack = removeBack;

/**
Removes all elements belonging to $(D r), which must be a range
obtained originally from this container.

Returns: A range spanning the remaining elements in the container that
initially were right after $(D r).

Complexity: $(BIGOH 1)
     */
    Range remove(Range r)
    {
        if (r.empty)
            return r;

        assert(_root !is null, "Cannot remove from an un-initialized List");
        assert(r._first, "Remove: Range is empty");

        BaseNode.connect(r._first._prev, r._last._next);
        auto after = r._last._next;
        if (after is _root)
            return Range(null, null);
        else
            return Range(after, _last);
    }

    /// ditto
    Range linearRemove(Range r)
    {
         return remove(r);
    }

/**
$(D linearRemove) functions as $(D remove), but also accepts ranges that are
result the of a $(D take) operation. This is a convenient way to remove a
fixed amount of elements from the range.

Complexity: $(BIGOH r.walkLength)
     */
    Range linearRemove(Take!Range r)
    {
        assert(_root !is null, "Cannot remove from an un-initialized List");
        assert(r.source._first, "Remove: Range is empty");

        BaseNode* first = r.source._first;
        BaseNode* last = null;
        do
        {
            last = r.source._first;
            r.popFront();
        } while ( !r.empty );

        return remove(Range(first, last));
    }

    /// ditto
    alias stableRemove = remove;
    /// ditto
    alias stableLinearRemove = linearRemove;

private:

    // Helper: Inserts stuff before the node n.
    size_t insertBeforeNode(Stuff)(BaseNode* n, ref Stuff stuff)
    if (isImplicitlyConvertible!(Stuff, T))
    {
        auto p = createNode(stuff, n._prev, n);
        n._prev._next = p;
        n._prev = p;
        return 1;
    }
    // ditto
    size_t insertBeforeNode(Stuff)(BaseNode* n, ref Stuff stuff)
    if (isInputRange!Stuff && isImplicitlyConvertible!(ElementType!Stuff, T))
    {
        if (stuff.empty) return 0;
        size_t result;
        Range r = createRange(stuff, result);
        BaseNode.connect(n._prev, r._first);
        BaseNode.connect(r._last, n);
        return result;
    }

    // Helper: Inserts stuff after the node n.
    size_t insertAfterNode(Stuff)(BaseNode* n, ref Stuff stuff)
    if (isImplicitlyConvertible!(Stuff, T))
    {
        auto p = createNode(stuff, n, n._next);
        n._next._prev = p;
        n._next = p;
        return 1;
    }
    // ditto
    size_t insertAfterNode(Stuff)(BaseNode* n, ref Stuff stuff)
    if (isInputRange!Stuff && isImplicitlyConvertible!(ElementType!Stuff, T))
    {
        if (stuff.empty) return 0;
        size_t result;
        Range r = createRange(stuff, result);
        BaseNode.connect(r._last, n._next);
        BaseNode.connect(n, r._first);
        return result;
    }

    // Helper: Creates a chain of nodes from the range stuff.
    Range createRange(Stuff)(ref Stuff stuff, ref size_t result)
    {
        BaseNode* first = createNode(stuff.front);
        BaseNode* last = first;
        ++result;
        for ( stuff.popFront() ; !stuff.empty ; stuff.popFront() )
        {
            auto p = createNode(stuff.front, last);
            last = last._next = p;
            ++result;
        }
        return Range(first, last);
    }
}

@safe unittest
{
    import std.algorithm : equal;

    //Tests construction signatures
    alias IntList = DList!int;
    auto a0 = IntList();
    auto a1 = IntList(0);
    auto a2 = IntList(0, 1);
    auto a3 = IntList([0]);
    auto a4 = IntList([0, 1]);

    assert(a0[].empty);
    assert(equal(a1[], [0]));
    assert(equal(a2[], [0, 1]));
    assert(equal(a3[], [0]));
    assert(equal(a4[], [0, 1]));
}

@safe unittest
{
    import std.algorithm : equal;

    alias IntList = DList!int;
    IntList list = IntList([0,1,2,3]);
    assert(equal(list[],[0,1,2,3]));
    list.insertBack([4,5,6,7]);
    assert(equal(list[],[0,1,2,3,4,5,6,7]));

    list = IntList();
    list.insertFront([0,1,2,3]);
    assert(equal(list[],[0,1,2,3]));
    list.insertFront([4,5,6,7]);
    assert(equal(list[],[4,5,6,7,0,1,2,3]));
}

@safe unittest
{
    import std.algorithm : equal;
    import std.range : take;

    alias IntList = DList!int;
    IntList list = IntList([0,1,2,3]);
    auto range = list[];
    for( ; !range.empty; range.popFront())
    {
        int item = range.front;
        if (item == 2)
        {
            list.stableLinearRemove(take(range, 1));
            break;
        }
    }
    assert(equal(list[],[0,1,3]));

    list = IntList([0,1,2,3]);
    range = list[];
    for( ; !range.empty; range.popFront())
    {
        int item = range.front;
        if (item == 2)
        {
            list.stableLinearRemove(take(range,2));
            break;
        }
    }
    assert(equal(list[],[0,1]));

    list = IntList([0,1,2,3]);
    range = list[];
    for( ; !range.empty; range.popFront())
    {
        int item = range.front;
        if (item == 0)
        {
            list.stableLinearRemove(take(range,2));
            break;
        }
    }
    assert(equal(list[],[2,3]));

    list = IntList([0,1,2,3]);
    range = list[];
    for( ; !range.empty; range.popFront())
    {
        int item = range.front;
        if (item == 1)
        {
            list.stableLinearRemove(take(range,2));
            break;
        }
    }
    assert(equal(list[],[0,3]));
}

@safe unittest
{
    import std.algorithm : equal;

    auto dl = DList!string(["a", "b", "d"]);
    dl.insertAfter(dl[], "e"); // insert at the end
    assert(equal(dl[], ["a", "b", "d", "e"]));
    auto dlr = dl[];
    dlr.popBack(); dlr.popBack();
    dl.insertAfter(dlr, "c"); // insert after "b"
    assert(equal(dl[], ["a", "b", "c", "d", "e"]));
}

@safe unittest
{
    import std.algorithm : equal;

    auto dl = DList!string(["a", "b", "d"]);
    dl.insertBefore(dl[], "e"); // insert at the front
    assert(equal(dl[], ["e", "a", "b", "d"]));
    auto dlr = dl[];
    dlr.popFront(); dlr.popFront();
    dl.insertBefore(dlr, "c"); // insert before "b"
    assert(equal(dl[], ["e", "a", "c", "b", "d"]));
}

@safe unittest
{
    auto d = DList!int([1, 2, 3]);
    d.front = 5; //test frontAssign
    assert(d.front == 5);
    auto r = d[];
    r.back = 1;
    assert(r.back == 1);
}

// Issue 8895
@safe unittest
{
    auto a = make!(DList!int)(1,2,3,4);
    auto b = make!(DList!int)(1,2,3,4);
    auto c = make!(DList!int)(1,2,3,5);
    auto d = make!(DList!int)(1,2,3,4,5);
    assert(a == b); // this better terminate!
    assert(!(a == c));
    assert(!(a == d));
}

@safe unittest
{
    auto d = DList!int([1, 2, 3]);
    d.front = 5; //test frontAssign
    assert(d.front == 5);
    auto r = d[];
    r.back = 1;
    assert(r.back == 1);
}

@safe unittest
{
    auto a = DList!int();
    assert(a.removeFront(10) == 0);
    a.insert([1, 2, 3]);
    assert(a.removeFront(10) == 3);
    assert(a[].empty);
}

@safe unittest
{
    import std.algorithm : equal;

    //Verify all flavors of ~
    auto a = DList!int();
    auto b = DList!int();
    auto c = DList!int([1, 2, 3]);
    auto d = DList!int([4, 5, 6]);

    assert((a ~ b[])[].empty);
    assert((c ~ d[])[].equal([1, 2, 3, 4, 5, 6]));
    assert(c[].equal([1, 2, 3]));
    assert(d[].equal([4, 5, 6]));

    assert((c[] ~ d)[].equal([1, 2, 3, 4, 5, 6]));
    assert(c[].equal([1, 2, 3]));
    assert(d[].equal([4, 5, 6]));

    a~=c[];
    assert(a[].equal([1, 2, 3]));
    assert(c[].equal([1, 2, 3]));

    a~=d[];
    assert(a[].equal([1, 2, 3, 4, 5, 6]));
    assert(d[].equal([4, 5, 6]));

    a~=[7, 8, 9];
    assert(a[].equal([1, 2, 3, 4, 5, 6, 7, 8, 9]));

    //trick test:
    auto r = c[];
    c.removeFront();
    c.removeBack();
}

@safe unittest
{
    import std.algorithm : equal;

    //8905
    auto a = DList!int([1, 2, 3, 4]);
    auto r = a[];
    a.stableRemoveBack();
    a.stableInsertBack(7);
    assert(a[].equal([1, 2, 3, 7]));
}

@safe unittest //12566
{
    auto dl2 = DList!int([2,7]);
    dl2.removeFront();
    assert(dl2[].walkLength == 1);
    dl2.removeBack();
    assert(dl2.empty, "not empty?!");
}

@safe unittest //13076
{
    DList!int list;
    assert(list.empty);
    list.clear();
}

@safe unittest //13425
{
    import std.range : drop, take;
    auto list = DList!int([1,2,3,4,5]);
    auto r = list[].drop(4); // r is a view of the last element of list
    assert(r.front == 5 && r.walkLength == 1);
    r = list.linearRemove(r.take(1));
    assert(r.empty); // fails
}
