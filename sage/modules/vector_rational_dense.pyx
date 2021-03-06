"""
Vectors with rational entries. 

AUTHOR:

- William Stein (2007)
- Soroosh Yazdani (2007)

EXAMPLES::

    sage: v = vector(QQ,[1,2,3,4,5])
    sage: v
    (1, 2, 3, 4, 5)
    sage: 3*v
    (3, 6, 9, 12, 15)
    sage: v/2
    (1/2, 1, 3/2, 2, 5/2)
    sage: -v
    (-1, -2, -3, -4, -5)
    sage: v - v
    (0, 0, 0, 0, 0)
    sage: v + v
    (2, 4, 6, 8, 10)
    sage: v * v
    55

We make a large zero vector::

    sage: k = QQ^100000; k
    Vector space of dimension 100000 over Rational Field
    sage: v = k(0)
    sage: v[:10]
    (0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

TESTS::

    sage: v = vector(QQ, [1,2/5,-3/8,4])
    sage: loads(dumps(v)) == v
    True
"""

###############################################################################
#   Sage: System for Algebra and Geometry Experimentation    
#       Copyright (C) 2007 William Stein <wstein@gmail.com>
#  Distributed under the terms of the GNU General Public License (GPL)
#                  http://www.gnu.org/licenses/
###############################################################################

include '../ext/interrupt.pxi'
include '../ext/stdsage.pxi'

from sage.structure.element cimport Element, ModuleElement, RingElement, Vector

from sage.rings.integer cimport Integer
from sage.rings.rational cimport Rational

cimport free_module_element
from free_module_element import vector

cdef inline _Rational_from_mpq(mpq_t e):
    cdef Rational z = PY_NEW(Rational)
    mpq_set(z.value, e)
    return z

cdef class Vector_rational_dense(free_module_element.FreeModuleElement):
    cdef bint is_dense_c(self):
        return 1
    cdef bint is_sparse_c(self):
        return 0

    cdef _new_c(self):
        cdef Vector_rational_dense y
        y = PY_NEW(Vector_rational_dense)
        y._init(self._degree, self._parent)
        return y

    def __copy__(self):
        cdef Vector_rational_dense y
        y = self._new_c()
        cdef Py_ssize_t i
        for i from 0 <= i < self._degree:
            mpq_init(y._entries[i])
            mpq_set(y._entries[i], self._entries[i])
        return y

    cdef _init(self, Py_ssize_t degree, parent):
        self._degree = degree
        self._parent = parent
        self._entries = <mpq_t *> sage_malloc(sizeof(mpq_t) * degree)
        if self._entries == NULL:
            raise MemoryError
        
    def __cinit__(self, parent=None, x=None, coerce=True,copy=True):
        self._entries = NULL
        self._is_mutable = 1
        if not parent is None:
            self._init(parent.degree(), parent)

    def __init__(self, parent, x, coerce=True, copy=True):
        cdef Py_ssize_t i
        cdef Rational z
        # we have to do this to avoid a garbage collection error in dealloc
        for i from 0 <= i < self._degree:
            mpq_init(self._entries[i])
        if isinstance(x, (list, tuple)):
            if len(x) != self._degree:
                raise TypeError("entries must be a list of length %s"%self._degree)
            for i from 0 <= i < self._degree:
                z = Rational(x[i])
                mpq_set(self._entries[i], z.value)
            return
        if x != 0:
            raise TypeError("can't initialize vector from nonzero non-list")
                
    def __dealloc__(self):
        cdef Py_ssize_t i
        if self._entries:
            sig_on()
            for i from 0 <= i < self._degree:
                #print "clearing gmp's entry %s"%i
                mpq_clear(self._entries[i])
            sig_off()
            #print "clearing python entries"
            sage_free(self._entries)

    cdef int _cmp_c_impl(left, Element right) except -2:
        """
        EXAMPLES::

            sage: v = vector(QQ, [0,0,0,0])
            sage: v == 0
            True
            sage: v == 1
            False
            sage: v == v
            True
            sage: w = vector(QQ, [-1,3/2,0,0])
            sage: w < v
            True
            sage: w > v
            False
        """
        cdef Py_ssize_t i
        cdef int c
        for i from 0 <= i < left.degree():
            c = mpq_cmp(left._entries[i], (<Vector_rational_dense>right)._entries[i])
            if c < 0:
                return -1
            elif c > 0:
                return 1
        return 0

    # see sage/structure/element.pyx
    def __richcmp__(left, right, int op):
        """
        TEST::

            sage: w = vector(QQ, [-1,0,0,0])
            sage: w == w
            True
        """
        return (<Element>left)._richcmp(right, op)

    # __hash__ is not properly inherited if comparison is changed
    def __hash__(self):
        """
        TEST::

            sage: w = vector(QQ, [-1,0,0,0])
            sage: w.set_immutable()
            sage: isinstance(hash(w), int)
            True
        """
        return free_module_element.FreeModuleElement.__hash__(self)

    def __len__(self):
        return self._degree

    def __setitem__(self, i, value):
        if not self._is_mutable:
            raise ValueError("vector is immutable; please change a copy instead (use copy())")
        cdef Rational z
        cdef Py_ssize_t k, d, n
        if isinstance(i, slice):
            start, stop = i.start, i.stop
            d = self.degree()
            R = self.base_ring()
            n = 0
            for k from start <= k < stop:
                if k >= d:
                    return
                if k >= 0:
                    self[k] = R(value[n])
                    n = n + 1
        else:
            if i < 0 or i >= self._degree:
                raise IndexError
            else:
                z = Rational(value)
                mpq_set(self._entries[i], z.value)

    def __getitem__(self, i):
        """
        Returns `i`-th entry or slice of self.

        EXAMPLES::

            sage: v = vector([1/2,2/3,3/4]); v
            (1/2, 2/3, 3/4)
            sage: v[0]
            1/2
            sage: v[2]
            3/4
            sage: v[-2]
            2/3
            sage: v[5]
            Traceback (most recent call last):
            ...
            IndexError: index out of range
            sage: v[-5]
            Traceback (most recent call last):
            ...
            IndexError: index out of range
        """
        cdef Rational z = PY_NEW(Rational)
        if isinstance(i, slice):
            start, stop, step = i.indices(len(self))
            return vector(self.base_ring(), self.list()[start:stop])
        else:
            if i < 0:
                i += self._degree
            if i < 0 or i >= self._degree:
                raise IndexError('index out of range')
            else:
                mpq_set(z.value, self._entries[i])
                return z

    def list(self,copy=True):
        """
        The list of entries of the vector.

        INPUT:

        - ``copy``, ignored optional argument.

        EXAMPLES::

            sage: v = vector(QQ,[1,2,3,4])
            sage: a = v.list(copy=False); a
            [1, 2, 3, 4]
            sage: a[0] = 0
            sage: v
            (1, 2, 3, 4)
        """
        cdef int i
        return [_Rational_from_mpq(self._entries[i]) for i in
                                  xrange(self._degree)]

    def __reduce__(self):
        return (unpickle_v1, (self._parent, self.list(), self._degree, self._is_mutable))

    cpdef ModuleElement _add_(self, ModuleElement right):
        cdef Vector_rational_dense z, r
        r = right
        z = self._new_c()
        cdef Py_ssize_t i
        for i from 0 <= i < self._degree:
            mpq_init(z._entries[i])
            mpq_add(z._entries[i], self._entries[i], r._entries[i])
        return z
        

    cpdef ModuleElement _sub_(self, ModuleElement right):
        cdef Vector_rational_dense z, r
        r = right
        z = self._new_c()
        cdef Py_ssize_t i
        for i from 0 <= i < self._degree:
            mpq_init(z._entries[i])
            mpq_sub(z._entries[i], self._entries[i], r._entries[i])
        return z
        
    cpdef Element _dot_product_(self, Vector right):
        """
        Dot product of dense vectors over the rationals.
        
        EXAMPLES::

            sage: v = vector(QQ, [1,2,-3]); w = vector(QQ,[4,3,2])
            sage: v*w
            4
            sage: w*v
            4
        """
        cdef Vector_rational_dense r = right
        cdef Rational z
        z = PY_NEW(Rational)
        cdef mpq_t t
        mpq_init(t)
        mpq_set_si(z.value, 0, 1)
        cdef Py_ssize_t i
        for i from 0 <= i < self._degree:
            mpq_mul(t, self._entries[i], r._entries[i])
            mpq_add(z.value, z.value, t)
        mpq_clear(t)
        return z
        

    cpdef Vector _pairwise_product_(self, Vector right):
        """
        EXAMPLES::

            sage: v = vector(QQ, [1,2,-3]); w = vector(QQ,[4,3,2])
            sage: v.pairwise_product(w)
            (4, 6, -6)
        """
        cdef Vector_rational_dense z, r
        r = right
        z = self._new_c()
        cdef Py_ssize_t i
        for i from 0 <= i < self._degree:
            mpq_init(z._entries[i])
            mpq_mul(z._entries[i], self._entries[i], r._entries[i])
        return z
        
    cpdef ModuleElement _rmul_(self, RingElement left):
        cdef Vector_rational_dense z
        cdef Rational a
        if PY_TYPE_CHECK(left, Rational):
            a = <Rational>left
        elif PY_TYPE_CHECK(left, Integer):
            a = <Rational>PY_NEW(Rational)
            mpq_set_z(a.value, (<Integer>left).value)
        else:
            # should not happen
            raise TypeError("Cannot convert %s to %s" % (type(left).__name__, Rational.__name__))
        z = self._new_c()
        cdef Py_ssize_t i
        for i from 0 <= i < self._degree:
            mpq_init(z._entries[i])
            mpq_mul(z._entries[i], self._entries[i], a.value)
        return z


    cpdef ModuleElement _lmul_(self, RingElement right):
        cdef Vector_rational_dense z
        cdef Rational a
        if PY_TYPE_CHECK(right, Rational):
            a = <Rational>right
        elif PY_TYPE_CHECK(right, Integer):
            a = <Rational>PY_NEW(Rational)
            mpq_set_z(a.value, (<Integer>right).value)
        else:
            # should not happen
            raise TypeError("Cannot convert %s to %s" % (type(right).__name__, Rational.__name__))
        z = self._new_c()
        cdef Py_ssize_t i
        for i from 0 <= i < self._degree:
            mpq_init(z._entries[i])
            mpq_mul(z._entries[i], self._entries[i], a.value)
        return z

    cpdef ModuleElement _neg_(self):
        cdef Vector_rational_dense z
        z = self._new_c()
        cdef Py_ssize_t i
        for i from 0 <= i < self._degree:
            mpq_init(z._entries[i])
            mpq_neg(z._entries[i], self._entries[i])
        return z


def unpickle_v0(parent, entries, degree):
    # If you think you want to change this function, don't.
    # Instead make a new version with a name like
    #    make_FreeModuleElement_generic_dense_v1
    # and changed the reduce method below.
    cdef Vector_rational_dense v
    v = PY_NEW(Vector_rational_dense)
    v._init(degree, parent)
    cdef Rational z
    for i from 0 <= i < degree:
        z = Rational(entries[i])
        mpq_init(v._entries[i])
        mpq_set(v._entries[i], z.value)
    return v

def unpickle_v1(parent, entries, degree, is_mutable):
    cdef Vector_rational_dense v
    v = PY_NEW(Vector_rational_dense)
    v._init(degree, parent)
    cdef Rational z
    for i from 0 <= i < degree:
        z = Rational(entries[i])
        mpq_init(v._entries[i])
        mpq_set(v._entries[i], z.value)
    v._is_mutable = is_mutable
    return v
