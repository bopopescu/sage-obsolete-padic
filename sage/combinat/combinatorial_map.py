"""
Combinatorial maps
"""
#*****************************************************************************
#       Copyright (C) 2011 Christian Stump <christian.stump at gmail.com>
#
#  Distributed under the terms of the GNU General Public License (GPL)
#                  http://www.gnu.org/licenses/
#*****************************************************************************

def combinatorial_map(f=None, order=None, name=None):
    r"""
    Combinatorial maps

    We call a method a *combinatorial map* if it is a map between two
    combinatorial sets.

    INPUT:

    - ``f`` -- (default: ``None``, if combinatorial_map is used as a decorator) a function
    - ``name`` -- (default: ``None``) the name for nicer outputs on combinatorial maps
    - ``order`` -- (default: ``None``) the order of the combinatorial map, if it is known. Is not used, but might be helpful later

    OUTPUT:

    - A combinatorial map. This is an instance of the :class:`CombinatorialMap`

    The decorator :obj:`combinatorial_map` can be used to declare
    methods as combinatorial maps.

    EXAMPLES::

        sage: p = Permutation([1,3,2,4])
        sage: p.left_tableau
        Combinatorial map: Robinson-Schensted insertion tableau

    We define a class illustrating the use of the decorator
    :obj:`combinatorial_map` with the various arguments::

        sage: from sage.combinat.combinatorial_map import combinatorial_map
        sage: class MyPermutation(object):
        ...
        ...       @combinatorial_map()
        ...       def reverse(self):
        ...           '''
        ...           Reverse the permutation
        ...           '''
        ...           pass
        ...
        ...       @combinatorial_map(order=2)
        ...       def inverse(self):
        ...           '''
        ...           The inverse of the permutation
        ...           '''
        ...           pass
        ...
        ...       @combinatorial_map(name='descent set of permutation')
        ...       def descent_set(self):
        ...           '''
        ...           The descent set of the permutation
        ...           '''
        ...           pass
        ...
        ...       def major_index(self):
        ...           '''
        ...           The major index of the permutation
        ...           '''
        ...           pass
        sage: MyPermutation.reverse
        Combinatorial map: reverse
        sage: MyPermutation.descent_set
        Combinatorial map: descent set of permutation
        sage: MyPermutation.inverse
        Combinatorial map: inverse

    One can determine all the combinatorial maps associated with a given object
    as follows::

        sage: from sage.combinat.combinatorial_map import combinatorial_maps_in_class
        sage: X = combinatorial_maps_in_class(MyPermutation); X # random
        [Combinatorial map: reverse,
         Combinatorial map: descent set of permutation,
         Combinatorial map: inverse]

    The method ``major_index`` defined about is not a combinatorial map::

        sage: MyPermutation.major_index
        <unbound method MyPermutation.major_index>

    But one can define a function that turns ``major_index`` into a combinatorial map::

        sage: def major_index(p):
        ...       return p.major_index()
        ...
        sage: major_index
        <function major_index at ...>
        sage: combinatorial_map(major_index)
        Combinatorial map: major_index

    """
    if f is None:
        return lambda f: CombinatorialMap(f, order=order, name=name)
    else:
        return CombinatorialMap(f, order=order, name=name)

class CombinatorialMap(object):
    r"""
    This is a wrapper class for methods that are *combinatorial maps*.

    For further details and doctests, see :func:`combinatorial_map`.
    """
    def __init__(self, f, order=None, name=None):
        """
        Constructor for combinatorial maps

        EXAMPLES::

            sage: from sage.combinat.combinatorial_map import combinatorial_map
            sage: def f(x):
            ...       "doc of f"
            ...       return x
            ...
            sage: x = combinatorial_map(f); x
            Combinatorial map: f
            sage: x.__doc__
            'doc of f'
            sage: x.__name__
            'f'
            sage: x.__module__
            '__main__'
        """
        import types
        if not isinstance(f, types.FunctionType):
            raise ValueError, "Only plain functions are supported"
        self._f = f
        self._order = order
        self._name = name
        if hasattr(f, "func_doc"):
            self.__doc__ = f.func_doc
        if hasattr(f, "func_name"):
            self.__name__ = f.func_name
        else:
            self.__name__ = "..."
        if hasattr(f, "__module__"):
            self.__module__ = f.__module__

    def __repr__(self):
        """
        EXAMPLES::

            sage: p = Permutation([1,3,2,4])
            sage: p.left_tableau.__repr__()
            'Combinatorial map: Robinson-Schensted insertion tableau'
        """
        name = self._name if self._name else self.__name__
        return "Combinatorial map: %s" % name

    def _sage_src_lines_(self):
        """
        Returns the source code location for the wrapped function.

        EXAMPLES::

            sage: p = Permutation([1,3,2,4])
            sage: cm = p.left_tableau; cm
            Combinatorial map: Robinson-Schensted insertion tableau
            sage: (src, lines) = cm._sage_src_lines_()
            sage: src[0]
            "    @combinatorial_map(name='Robinson-Schensted insertion tableau')\n"
            sage: lines # random
            2653
        """
        from sage.misc.sageinspect import sage_getsourcelines
        return sage_getsourcelines(self._f)

    def __get__(self, inst, cls=None):
        """
        Bounds the method of self to the given instance.

        EXAMPLES::

            sage: p = Permutation([1,3,2,4])
            sage: p.left_tableau #indirect doctest
            Combinatorial map: Robinson-Schensted insertion tableau
        """
        self._inst = inst
        return self

    def __call__(self, *args, **kwds):
        """
        Calls the combinatorial map.

        EXAMPLES::

            sage: p = Permutation([1,3,2,4])
            sage: cm = type(p).left_tableau; cm
            Combinatorial map: Robinson-Schensted insertion tableau
            sage: cm(p)
            [[1, 2, 4], [3]]
            sage: cm(Permutation([4,3,2,1]))
            [[1], [2], [3], [4]]
        """
        if self._inst is not None:
            return self._f(self._inst, *args, **kwds)
        else:
            return self._f(*args, **kwds)

    def order(self):
        """
        Returns the order of ``self``, or ``None`` if the order is not known.

        EXAMPLES::

            sage: from sage.combinat.combinatorial_map import combinatorial_map
            sage: class CombinatorialClass:
            ...       @combinatorial_map(order=2)
            ...       def to_self_1(): pass
            ...       @combinatorial_map()
            ...       def to_self_2(): pass
            sage: CombinatorialClass.to_self_1.order()
            2
            sage: CombinatorialClass.to_self_2.order() is None
            True
        """
        return self._order

    def name(self):
        """
        If given, returns the name of a combinatorial map; ``None`` otherwise.
        This is used for the string representation of ``self``.

        EXAMPLES::

            sage: from sage.combinat.combinatorial_map import combinatorial_map
            sage: class CombinatorialClass:
            ...       @combinatorial_map(name='map1')
            ...       def to_self_1(): pass
            ...       @combinatorial_map()
            ...       def to_self_2(): pass
            sage: CombinatorialClass.to_self_1.name()
            'map1'
            sage: CombinatorialClass.to_self_2.name() is None
            True
        """
        return self._name

def combinatorial_maps_in_class(cls):
    """
    Returns the combinatorial maps of the class as a list of combinatorial maps.

    EXAMPLES::

        sage: from sage.combinat.combinatorial_map import combinatorial_maps_in_class
        sage: p = Permutation([1,3,2,4])
        sage: cmaps = combinatorial_maps_in_class(p)
        sage: cmaps # random
        [Combinatorial map: Robinson-Schensted insertion tableau,
         Combinatorial map: Robinson-Schensted recording tableau,
         Combinatorial map: Robinson-Schensted tableau shape,
         Combinatorial map: complement,
         Combinatorial map: descent composition,
         Combinatorial map: inverse, ...]
        sage: p.left_tableau in cmaps
        True
        sage: p.right_tableau in cmaps
        True
        sage: p.complement in cmaps
        True
    """
    result = set()
    for method in dir(cls):
        entry = getattr(cls, method)
        if isinstance(entry, CombinatorialMap):
            result.add(entry)
    return list(result)
