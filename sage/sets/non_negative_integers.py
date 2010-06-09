"""
Non Negative Integers
"""
#*****************************************************************************
#  Copyright (C) 2009 Florent Hivert <Florent.Hivert@univ-rouen.fr>
#
#  Distributed under the terms of the GNU General Public License (GPL)
#                  http://www.gnu.org/licenses/
#*****************************************************************************

from sage.structure.parent import Parent
from sage.categories.infinite_enumerated_sets import InfiniteEnumeratedSets
from sage.structure.unique_representation import UniqueRepresentation
from sage.rings.integer import Integer

class NonNegativeIntegers(UniqueRepresentation, Parent):
    r"""
    The enumerated set of non negative integers.

    This class implements the set of non negative integers, as an
    enumerated set (see :class:`InfiniteEnumeratedSets 
    <sage.categories.infinite_enumerated_sets.InfiniteEnumeratedSets>`).

    EXAMPLES::

        sage: NN = NonNegativeIntegers()
        sage: NN
        Non negative integers
        sage: NN.cardinality()
        +Infinity
        sage: TestSuite(NN).run()
        sage: NN.list()
        Traceback (most recent call last):
        ...
        NotImplementedError: infinite list
        sage: NN.element_class
        <type 'sage.rings.integer.Integer'>
        sage: it = iter(NN)
        sage: [it.next(), it.next(), it.next(), it.next(), it.next()]
        [0, 1, 2, 3, 4]
        sage: NN.first()
        0

    Currently, this is just a "facade" parent; namely its elements are
    plain Sage ``Integers`` with ``Integer Ring`` as parent::

        sage: x = NN(15); type(x)
        <type 'sage.rings.integer.Integer'>
        sage: x.parent()
        Integer Ring
        sage: x+3
        18

    In a later version, there will be an option to specify whether the
    elements should have ``Integer Ring`` or ``Non negative integers``
    as parent::

        sage: NN = NonNegativeIntegers(facade = False) # todo: not implemented
        sage: x = NN(5)                                # todo: not implemented
        sage: x.parent()                               # todo: not implemented
        Non negative integers

    This runs generic sanity checks on ``NN``::

        sage: TestSuite(NN).run()

    TODO: do not use ``NN`` any more in the doctests for
    ``NonNegativeIntegers``.
    """

    def __init__(self, category=None):
        """
        TESTS::

            sage: NN = NonNegativeIntegers()
            sage: NN
            Non negative integers
            sage: NN.category()
            Category of infinite enumerated sets
            sage: TestSuite(NN).run()
        """
        Parent.__init__(self, category = InfiniteEnumeratedSets().or_subcategory(category) )

    def _repr_(self):
        """
        TESTS::

            sage: NonNegativeIntegers() # indirect doctest
            Non negative integers
        """
        return "Non negative integers"

    def __contains__(self, elt):
        """
        EXAMPLES::

            sage: NN = NonNegativeIntegers()
            sage: 1 in NN
            True
            sage: -1 in NN
            False
            sage: x in NN
            False
        """
        try:
            return Integer(elt) >= Integer(0)
        except TypeError:
            return False

    def _element_constructor_(self, i):
        """
        Constructs an element of self from an integer, testing that
        this integer is indeed non negative.

        EXAMPLES::

            sage: NN = NonNegativeIntegers()
            sage: NN._element_constructor_(42)
            42
            sage: NN._element_constructor_(-5)
            Traceback (most recent call last):
            ...
            ValueError: Value -5 in not in Non negative integers.
            sage: NN._element_constructor_(x)
            Traceback (most recent call last):
            ...
            ValueError: Value x in not in Non negative integers.

        This is used upon coercion attempts::

            sage: n = NN(42); n                  # indirect doctest
            42
            sage: type(n)
            <type 'sage.rings.integer.Integer'>
            sage: n.parent()
            Integer Ring
            sage: NN(-1)
            Traceback (most recent call last):
            ...
            ValueError: Value -1 in not in Non negative integers.

        For fast construction of elements without tests, please use
        instead ``from_integer``::

            sage: NN.from_integer(42)
            42
            sage: NN.from_integer(-5)            # Don't do that at home kids!
            -5
        """
        if i in self:
            return self.from_integer(i)
        else:
            raise ValueError, "Value %s in not in %s."%(i, self)

    from_integer = Integer

    Element = Integer

    def __iter__(self):
        """
        EXAMPLES::

            sage: NN = NonNegativeIntegers()
            sage: g = iter(NN)
            sage: g.next(), g.next(), g.next(), g.next()
            (0, 1, 2, 3)
        """
        i = 0
        while True:
            yield self.from_integer(i)
            i += 1
            # Uncomment the following two lines to catch infinite loops when debugging
            #if i > 200:
            #    raise ValueError, "Infinite loop during DEBUG! TODO: remove me"

    def an_element(self):
        """
        EXAMPLES::

            sage: NonNegativeIntegers().an_element()
            42
        """
        return self.from_integer(Integer(42))

    def some_elements(self):
        """
        EXAMPLES::

            sage: NonNegativeIntegers().some_elements()
            [0, 1, 3, 42]
        """
        return [Integer(0), Integer(1), Integer(3), Integer(42)]

    def next(self, o):
        """
        EXAMPLES::

            sage: NN = NonNegativeIntegers()
            sage: NN.next(3)
            4
        """
        return self.from_integer(o+1)

    def unrank(self, rnk):
        """
        EXAMPLES::

            sage: NN = NonNegativeIntegers()
            sage: NN.unrank(100)
            100
        """
        return self.from_integer(rnk)
