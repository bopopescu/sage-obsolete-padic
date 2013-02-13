r"""
ClusterSeed

A *cluster seed* is a pair `(B,\mathbf{x})` with `B` being a *skew-symmetrizable* `(n+m \times n)` *-matrix*
and with `\mathbf{x}` being an `n`-tuple of *independent elements* in the field of rational functions in `n` variables.

For the compendium on the cluster algebra and quiver package see

http://arxiv.org/abs/1102.4844.

AUTHORS:

- Gregg Musiker
- Christian Stump

.. seealso:: For mutation types of cluster seeds, see :meth:`sage.combinat.cluster_algebra_quiver.quiver_mutation_type.QuiverMutationType`. Cluster seeds are closely related to :meth:`sage.combinat.cluster_algebra_quiver.quiver.ClusterQuiver`.
"""

#*****************************************************************************
#       Copyright (C) 2011 Gregg Musiker <musiker@math.mit.edu>
#                          Christian Stump <christian.stump@univie.ac.at>
#
#  Distributed under the terms of the GNU General Public License (GPL)
#                  http://www.gnu.org/licenses/
#*****************************************************************************
import time
from sage.structure.sage_object import SageObject
from copy import copy
from sage.structure.unique_representation import UniqueRepresentation
from sage.misc.all import cached_method
from sage.rings.all import ZZ, QQ, infinity
from sage.rings.all import FractionField, PolynomialRing
from sage.rings.fraction_field_element import FractionFieldElement
from sage.sets.all import Set
from sage.graphs.all import Graph, DiGraph
from sage.combinat.cluster_algebra_quiver.quiver_mutation_type import QuiverMutationType, QuiverMutationType_Irreducible, QuiverMutationType_Reducible
from sage.groups.perm_gps.permgroup import PermutationGroup

class ClusterSeed(SageObject):
    r"""
    The *cluster seed* associated to an *exchange matrix*.

    INPUT:

    - ``data`` -- can be any of the following::

        * QuiverMutationType
        * str - a string representing a QuiverMutationType or a common quiver type (see Examples)
        * ClusterQuiver
        * Matrix - a skew-symmetrizable matrix
        * DiGraph - must be the input data for a quiver
        * List of edges - must be the edge list of a digraph for a quiver

    EXAMPLES::

        sage: S = ClusterSeed(['A',5]); S
        A seed for a cluster algebra of rank 5 of type ['A', 5]

        sage: S = ClusterSeed(['A',[2,5],1]); S
        A seed for a cluster algebra of rank 7 of type ['A', [2, 5], 1]

        sage: T = ClusterSeed( S ); T
        A seed for a cluster algebra of rank 7 of type ['A', [2, 5], 1]

        sage: T = ClusterSeed( S._M ); T
        A seed for a cluster algebra of rank 7

        sage: T = ClusterSeed( S.quiver()._digraph ); T
        A seed for a cluster algebra of rank 7

        sage: T = ClusterSeed( S.quiver()._digraph.edges() ); T
        A seed for a cluster algebra of rank 7

        sage: S = ClusterSeed(['B',2]); S
        A seed for a cluster algebra of rank 2 of type ['B', 2]

        sage: S = ClusterSeed(['C',2]); S
        A seed for a cluster algebra of rank 2 of type ['B', 2]

        sage: S = ClusterSeed(['A', [5,0],1]); S
        A seed for a cluster algebra of rank 5 of type ['D', 5] 

        sage: S = ClusterSeed(['GR',[3,7]]); S
        A seed for a cluster algebra of rank 6 of type ['E', 6] 

        sage: S = ClusterSeed(['F', 4, [2,1]]); S
        A seed for a cluster algebra of rank 6 of type ['F', 4, [1, 2]]
    """
    def __init__(self, data, frozen=None, is_principal=None):
        r"""
        TESTS::

            sage: S = ClusterSeed(['A',4])
            sage: TestSuite(S).run()
        """
        from quiver import ClusterQuiver
        from sage.matrix.matrix import Matrix

        # constructs a cluster seed from a cluster seed
        if type(data) is ClusterSeed:
            if frozen:
                print "The input \'frozen\' is ignored"
            self._M = copy( data._M )
            self._cluster = copy(data._cluster)
            self._n = data._n
            self._m = data._m
            self._R = data._R
            self._quiver = ClusterQuiver( data._quiver ) if data._quiver else None
            self._mutation_type = copy( data._mutation_type )
            self._description = copy( data._description )

        # constructs a cluster seed from a quiver
        elif type(data) is ClusterQuiver:
            if frozen:
                print "The input \'frozen\' is ignored"

            quiver = ClusterQuiver( data )
            self._M = copy(quiver._M)
            self._n = quiver._n
            self._m = quiver._m
            self._quiver = quiver
            self._mutation_type = quiver._mutation_type
            self._description = 'A seed for a cluster algebra of rank %d' %(self._n)
            self._R = FractionField(PolynomialRing(QQ,['x%s'%i for i in range(0,self._n)]+['y%s'%i for i in range(0,self._m)]))
            self._cluster = list(self._R.gens())

        # in all other cases, we construct the corresponding ClusterQuiver first
        else:
            quiver = ClusterQuiver( data, frozen=frozen )
            self.__init__( quiver )

        self._is_principal = is_principal

    def __eq__(self, other):
        r"""
        Returns True iff ``self`` represent the same cluster seed as ``other``.

        EXAMPLES::

            sage: S = ClusterSeed(['A',5])
            sage: T = S.mutate( 2, inplace=False )
            sage: S.__eq__( T )
            False

            sage: T.mutate( 2 )
            sage: S.__eq__( T )
            True
        """
        return type( other ) is ClusterSeed and self._M == other._M and self._cluster == other._cluster

    def _repr_(self):
        r"""
        Returns the description of ``self``.

        EXAMPLES::

            sage: S = ClusterSeed(['A',5])
            sage: S._repr_()
            "A seed for a cluster algebra of rank 5 of type ['A', 5]"
        """
        name = self._description
        if self._mutation_type:
            if type( self._mutation_type ) in [QuiverMutationType_Irreducible,QuiverMutationType_Reducible]:
                name += ' of type ' + str(self._mutation_type)
            # the following case will be relevant later on after ticket 13425 (mutation type checking) is applied
            else:
                name += ' of ' + self._mutation_type
        if self._m == 1:
            name += ' with %s frozen variable'%self._m
        elif self._m > 1:
            name += ' with %s frozen variables'%self._m
        return name

    def plot(self, circular=False, mark=None, save_pos=False):
        r"""
        Returns the plot of the quiver of ``self``.

        INPUT:

        - ``circular`` -- (default:False) if True, the circular plot is chosen, otherwise >>spring<< is used.
        - ``mark`` -- (default: None) if set to i, the vertex i is highlighted.
        - ``save_pos`` -- (default:False) if True, the positions of the vertices are saved.

        EXAMPLES::

            sage: S = ClusterSeed(['A',5])
            sage: pl = S.plot()
            sage: pl = S.plot(circular=True)
        """
        return self.quiver().plot(circular=circular,mark=mark,save_pos=save_pos)

    def show(self, fig_size=1, circular=False, mark=None, save_pos=False):
        r"""
        Shows the plot of the quiver of ``self``.

        INPUT:

        - ``fig_size`` -- (default: 1) factor by which the size of the plot is multiplied.
        - ``circular`` -- (default: False) if True, the circular plot is chosen, otherwise >>spring<< is used.
        - ``mark`` -- (default: None) if set to i, the vertex i is highlighted.
        - ``save_pos`` -- (default:False) if True, the positions of the vertices are saved.

        TESTS::

            sage: S = ClusterSeed(['A',5])
            sage: S.show() # long time
        """
        self.quiver().show(fig_size=fig_size, circular=circular,mark=mark,save_pos=save_pos)

    def interact(self, fig_size=1, circular=True):
        r"""
        Only in *notebook mode*. Starts an interactive window for cluster seed mutations.

        INPUT:

        - ``fig_size`` -- (default: 1) factor by which the size of the plot is multiplied.
        - ``circular`` -- (default: True) if True, the circular plot is chosen, otherwise >>spring<< is used.

        TESTS::

            sage: S = ClusterSeed(['A',4])
            sage: S.interact() # long time
            'The interactive mode only runs in the Sage notebook.'
        """
        from sage.plot.plot import EMBEDDED_MODE
        from sagenb.notebook.interact import interact, selector
        from sage.misc.all import html,latex
        from sage.all import var

        if not EMBEDDED_MODE:
            return "The interactive mode only runs in the Sage notebook."
        else:
            seq = []
            sft = [True]
            sss = [True]
            ssv = [True]
            ssm = [True]
            ssl = [True]
            @interact
            def player(k=selector(values=range(self._n),nrows = 1,label='Mutate at: '), show_seq=("Mutation sequence:", True), show_vars=("Cluster variables:", True), show_matrix=("B-Matrix:", True), show_lastmutation=("Show last mutation:", True) ):
                ft,ss,sv,sm,sl = sft.pop(), sss.pop(), ssv.pop(), ssm.pop(), ssl.pop()
                if ft:
                    self.show(fig_size=fig_size, circular=circular)
                elif show_seq is not ss or show_vars is not sv or show_matrix is not sm or show_lastmutation is not sl:
                    if seq and show_lastmutation:
                        self.show(fig_size=fig_size, circular=circular, mark=seq[len(seq)-1])
                    else:
                        self.show(fig_size=fig_size, circular=circular )
                else:
                    self.mutate(k)
                    seq.append(k)
                    if not show_lastmutation:
                        self.show(fig_size=fig_size, circular=circular)
                    else:
                        self.show(fig_size=fig_size, circular=circular,mark=k)
                sft.append(False)
                sss.append(show_seq)
                ssv.append(show_vars)
                ssm.append(show_matrix)
                ssl.append(show_lastmutation)
                if show_seq: html( "Mutation sequence: $" + str( [ seq[i] for i in xrange(len(seq)) ] ).strip('[]') + "$" )
                if show_vars:
                    html( "Cluster variables:" )
                    table = "$\\begin{align*}\n"
                    for i in xrange(self._n):
                        v = var('v%s'%i)
                        table += "\t" + latex( v ) + " &= " + latex( self._cluster[i] ) + "\\\\ \\\\\n"
                    table += "\\end{align*}$"
                    html( "$ $" )
                    html( table )
                    html( "$ $" )
                if show_matrix:
                    html( "B-Matrix:" )
                    m = self._M
                    #m = matrix(range(1,self._n+1),sparse=True).stack(m)
                    m = latex(m)
                    m = m.split('(')[1].split('\\right')[0]
                    html( "$ $" )
                    html( "$\\begin{align*} " + m + "\\end{align*}$" )
                    #html( "$" + m + "$" )
                    html( "$ $" )

    def save_image(self, filename, circular=False, mark=None, save_pos=False):
        r"""
        Saves the plot of the underlying digraph of the quiver of ``self``.

        INPUT:

        - ``filename`` -- the filename the image is saved to.
        - ``circular`` -- (default: False) if True, the circular plot is chosen, otherwise >>spring<< is used.
        - ``mark`` -- (default: None) if set to i, the vertex i is highlighted.
        - ``save_pos`` -- (default:False) if True, the positions of the vertices are saved.

        EXAMPLES::

            sage: Q = ClusterQuiver(['F',4,[1,2]])
            sage: Q.save_image(os.path.join(SAGE_TMP, 'sage.png'))
        """
        graph_plot = self.plot( circular=circular, mark=mark, save_pos=save_pos)
        graph_plot.save( filename=filename )

    def b_matrix(self):
        r"""
        Returns the `B` *-matrix* of ``self``.

        EXAMPLES::

            sage: ClusterSeed(['A',4]).b_matrix()
            [ 0  1  0  0]
            [-1  0 -1  0]
            [ 0  1  0  1]
            [ 0  0 -1  0]

            sage: ClusterSeed(['B',4]).b_matrix()
            [ 0  1  0  0]
            [-1  0 -1  0]
            [ 0  1  0  1]
            [ 0  0 -2  0]

            sage: ClusterSeed(['D',4]).b_matrix()
            [ 0  1  0  0]
            [-1  0 -1 -1]
            [ 0  1  0  0]
            [ 0  1  0  0]

            sage: ClusterSeed(QuiverMutationType([['A',2],['B',2]])).b_matrix()
            [ 0  1  0  0]
            [-1  0  0  0]
            [ 0  0  0  1]
            [ 0  0 -2  0]
        """
        return copy( self._M )

    def ground_field(self):
        r"""
        Returns the *ground field* of the cluster of ``self``.

        EXAMPLES::

            sage: S = ClusterSeed(['A',3])
            sage: S.ground_field()
            Fraction Field of Multivariate Polynomial Ring in x0, x1, x2 over Rational Field
        """
        return self._R

    def x(self,k):
        r"""
        Returns the `k` *-th initial cluster variable* for the associated cluster seed.

        EXAMPLES::

            sage: S = ClusterSeed(['A',3])
            sage: S.mutate([2,1])
            sage: S.x(0)
            x0

            sage: S.x(1)
            x1

            sage: S.x(2)
            x2
        """
        if k in range(self._n):
            x = self._R.gens()[k]
            return ClusterVariable( x.parent(), x.numerator(), x.denominator(), variable_type='cluster variable' )
        else:
            raise ValueError, "The input is not in an index of a cluster variable."

    def y(self,k):
        r"""
        Returns the `k` *-th initial coefficient (frozen variable)* for the associated cluster seed.

        EXAMPLES::

            sage: S = ClusterSeed(['A',3]).principal_extension()
            sage: S.mutate([2,1])
            sage: S.y(0)
            y0

            sage: S.y(1)
            y1

            sage: S.y(2)
            y2
        """
        if k in range(self._m):
            x = self._R.gens()[self._n+k]
            return ClusterVariable( x.parent(), x.numerator(), x.denominator(), variable_type='frozen variable' )
        else:
            raise ValueError, "The input is not in an index of a frozen variable."

    def mutation_type(self):
        """
        Returns the mutation type of self.

        EXAMPLES::

            sage: ClusterSeed(['A',4]).mutation_type()
            ['A', 4]
            sage: ClusterSeed(['A',(3,1),1]).mutation_type()
            ['A', [1, 3], 1]
            sage: ClusterSeed(['C',2]).mutation_type()
            ['B', 2]
            sage: ClusterSeed(['B',4,1]).mutation_type()
            ['BD', 4, 1]
        """
        return self._mutation_type

    def n(self):
        r"""
        Returns the number of *exchangeable variables* of ``self``.

        EXAMPLES::

            sage: S = ClusterSeed(['A',3])
            sage: S.n()
            3
        """
        return self._n

    def m(self):
        r"""
        Returns the number of *frozen variables* of ``self``.

        EXAMPLES::

            sage: S = ClusterSeed(['A',3])
            sage: S.n()
            3

            sage: S.m()
            0

            sage: S = S.principal_extension()
            sage: S.m()
            3
        """
        return self._m

    def cluster_variable(self,k):
        r"""
        Returns the `k`-th *cluster variable* of ``self``.

        EXAMPLES::

            sage: S = ClusterSeed(['A',3])
            sage: S.mutate([1,2])

            sage: [S.cluster_variable(k) for k in range(3)]
            [x0, (x0*x2 + 1)/x1, (x0*x2 + x1 + 1)/(x1*x2)]
        """
        if k not in range(self._n):
            raise ValueError("The cluster seed does not have a cluster variable of index %s."%k)
        f = self._cluster[k]
        return ClusterVariable( f.parent(), f.numerator(), f.denominator(), variable_type='cluster variable' )

    def cluster(self):
        r"""
        Returns the *cluster* of ``self``.

        EXAMPLES::

            sage: S = ClusterSeed(['A',3])
            sage: S.cluster()
            [x0, x1, x2]

            sage: S.mutate(1)
            sage: S.cluster()
            [x0, (x0*x2 + 1)/x1, x2]

            sage: S.mutate(2)
            sage: S.cluster()
            [x0, (x0*x2 + 1)/x1, (x0*x2 + x1 + 1)/(x1*x2)]

            sage: S.mutate([2,1])
            sage: S.cluster()
            [x0, x1, x2]
        """
        return [ self.cluster_variable(k) for k in range(self._n) ]

    def f_polynomial(self,k,ignore_coefficients=False):
        r"""
        Returns the ``k``-th *F-polynomial* of ``self``. It is obtained from the
        ``k``-th cluster variable by setting all `x_i` to `1`.

        EXAMPLES::

            sage: S = ClusterSeed(['A',3]).principal_extension()
            sage: S.mutate([2,1,2])
            sage: [S.f_polynomial(k) for k in range(3)]
            [1, y1*y2 + y2 + 1, y1 + 1]
        """
        if not (ignore_coefficients or self._is_principal):
            raise ValueError("No principal coefficients initialized. Use principal_extension, or ignore_coefficients to ignore this.")

        if self._m != self._n:
            raise ValueError("The F-polynomial is only defined if the number of frozen variables and the number of exchangeable variables coincide")
        if k not in range(self._n):
            raise ValueError("The cluster seed does not have a cluster variable of index %s."%k)
        eval_dict = dict( [ ( self.x(i), 1 ) for i in range(self._n) ] )
        return self.cluster_variable(k).subs(eval_dict)

    def f_polynomials(self,ignore_coefficients=False):
        r"""
        Returns all *F-polynomials* of ``self``. These are obtained from the
        cluster variables by setting all `x_i`'s to `1`.

        EXAMPLES::

            sage: S = ClusterSeed(['A',3]).principal_extension()
            sage: S.mutate([2,1,2])
            sage: S.f_polynomials()
            [1, y1*y2 + y2 + 1, y1 + 1]
        """
        if not (ignore_coefficients or self._is_principal):
            raise ValueError("No principal coefficients initialized. Use principal_extension, or ignore_coefficients to ignore this.")

        return [ self.f_polynomial(k,ignore_coefficients=ignore_coefficients) for k in range(self._n) ]

    def g_vector(self,k,ignore_coefficients=False):
        r"""
        Returns the ``k``-th *g-vector* of ``self``. This is the degree vector
        of the ``k``-th cluster variable after setting all `y_i`'s to `0`.

        EXAMPLES::

            sage: S = ClusterSeed(['A',3]).principal_extension()
            sage: S.mutate([2,1,2])
            sage: [ S.g_vector(k) for k in range(3) ]
            [(1, 0, 0), (0, 0, -1), (0, -1, 0)]
        """
        if not (ignore_coefficients or self._is_principal):
            raise ValueError("No principal coefficients initialized. Use principal_extension, or ignore_coefficients to ignore this.")

        if self._m != self._n:
            raise ValueError("The g-vector is only defined if the number of frozen variables and the number of exchangeable variables coincide")
        if k not in range(self._n):
            raise ValueError("The cluster seed does not have a cluster variable of index %s."%k)
        f = self.cluster_variable(k)
        eval_dict = dict( [ ( self.y(i), 0 ) for i in range(self._m) ] )
        f0 = f.subs(eval_dict)
        d1 = f0.numerator().degrees()
        d2 = f0.denominator().degrees()
        return tuple( d1[i] - d2[i] for i in range(self._n) )

    def g_matrix(self,ignore_coefficients=False):
        r"""
        Returns the matrix of all *g-vectors* of ``self``. This are the degree vectors
        of the cluster variables after setting all `y_i`'s to `0`.

        EXAMPLES::

            sage: S = ClusterSeed(['A',3]).principal_extension()
            sage: S.mutate([2,1,2])
            sage: S.g_matrix()
            [ 1  0  0]
            [ 0  0 -1]
            [ 0 -1  0]
        """
        from sage.matrix.all import matrix
        if not (ignore_coefficients or self._is_principal):
            raise ValueError("No principal coefficients initialized. Use principal_extension, or ignore_coefficients to ignore this.")
        return matrix( [ self.g_vector(k,ignore_coefficients=ignore_coefficients) for k in range(self._n) ] ).transpose()

    def c_vector(self,k,ignore_coefficients=False):
        r"""
        Returns the ``k``-th *c-vector* of ``self``. It is obtained as the
        ``k``-th column vector of the bottom part of the ``B``-matrix of ``self``.

        EXAMPLES::

            sage: S = ClusterSeed(['A',3]).principal_extension()
            sage: S.mutate([2,1,2])
            sage: [ S.c_vector(k) for k in range(3) ]
            [(1, 0, 0), (0, 0, -1), (0, -1, 0)]
        """
        if k not in range(self._n):
            raise ValueError("The cluster seed does not have a c-vector of index %s."%k)
        if not (ignore_coefficients or self._is_principal):
            raise ValueError("No principal coefficients initialized. Use principal_extension, or ignore_coefficients to ignore this.")
        return tuple( self._M[i,k] for i in range(self._n,self._n+self._m) )

    def c_matrix(self,ignore_coefficients=False):
        r"""
        Returns all *c-vectors* of ``self``.

        EXAMPLES::

            sage: S = ClusterSeed(['A',3]).principal_extension()
            sage: S.mutate([2,1,2])
            sage: S.c_matrix()
            [ 1  0  0]
            [ 0  0 -1]
            [ 0 -1  0]
        """
        if not (ignore_coefficients or self._is_principal):
            raise ValueError("No principal coefficients initialized. Use principal_extension, or ignore_coefficients to ignore this.")

        return self._M.submatrix(self._n,0)

    def coefficient(self,k):
        r"""
        Returns the *coefficient* of ``self`` at index ``k``.

        EXAMPLES::

            sage: S = ClusterSeed(['A',3]).principal_extension()
            sage: S.mutate([2,1,2])
            sage: [ S.coefficient(k) for k in range(3) ]
            [y0, 1/y2, 1/y1]
        """
        from sage.misc.all import prod
        if k not in range(self._n):
            raise ValueError("The cluster seed does not have a coefficient of index %s."%k)
        if self._m == 0:
            return self.x(0)**0
        #### Note: this special case m = 0 no longer needed except if we want type(answer) to be a cluster variable rather than an integer.
        else:
            exp = self.c_vector(k,ignore_coefficients=True)
            return prod( self.y(i)**exp[i] for i in xrange(self._m) )

    def coefficients(self):
        r"""
        Returns all *coefficients* of ``self``.

        EXAMPLES::

            sage: S = ClusterSeed(['A',3]).principal_extension()
            sage: S.mutate([2,1,2])
            sage: S.coefficients()
            [y0, 1/y2, 1/y1]
        """
        return [ self.coefficient(k) for k in range(self._n) ]

    def quiver(self):
        r"""
        Returns the *quiver* associated to ``self``.

        EXAMPLES::

            sage: S = ClusterSeed(['A',3])
            sage: S.quiver()
            Quiver on 3 vertices of type ['A', 3]
        """
        from sage.combinat.cluster_algebra_quiver.quiver import ClusterQuiver
        if self._quiver is None:
            self._quiver = ClusterQuiver( self._M )
        return self._quiver

    def is_acyclic(self):
        r"""
        Returns True iff self is acyclic (i.e., if the underlying quiver is acyclic).

        EXAMPLES::

            sage: ClusterSeed(['A',4]).is_acyclic()
            True

            sage: ClusterSeed(['A',[2,1],1]).is_acyclic()
            True

            sage: ClusterSeed([[0,1],[1,2],[2,0]]).is_acyclic()
            False
        """
        return self.quiver()._digraph.is_directed_acyclic()

    def is_bipartite(self,return_bipartition=False):
        r"""
        Returns True iff self is bipartite (i.e., if the underlying quiver is bipartite).

        INPUT:

        - return_bipartition -- (default:False) if True, the bipartition is returned in the case of ``self`` being bipartite.

        EXAMPLES::

            sage: ClusterQuiver(['A',[3,3],1]).is_bipartite()
            True

            sage: ClusterQuiver(['A',[4,3],1]).is_bipartite()
            False
        """
        return self.quiver().is_bipartite(return_bipartition=return_bipartition)

    def mutate(self, sequence, inplace=True):
        r"""
        Mutates ``self`` at a vertex or a sequence of vertices.

        INPUT:

        - ``sequence`` -- a vertex of self or an iterator of vertices of self.
        - ``inplace`` -- (default: True) if False, the result is returned, otherwise ``self`` is modified.

        EXAMPLES::

            sage: S = ClusterSeed(['A',4]); S.b_matrix()
            [ 0  1  0  0]
            [-1  0 -1  0]
            [ 0  1  0  1]
            [ 0  0 -1  0]

            sage: S.mutate(0); S.b_matrix()
            [ 0 -1  0  0]
            [ 1  0 -1  0]
            [ 0  1  0  1]
            [ 0  0 -1  0]

            sage: T = S.mutate(0, inplace=False); T
            A seed for a cluster algebra of rank 4 of type ['A', 4]

            sage: S.mutate(0)
            sage: S == T
            True

            sage: S.mutate([0,1,0])
            sage: S.b_matrix()
            [ 0 -1  1  0]
            [ 1  0  0  0]
            [-1  0  0  1]
            [ 0  0 -1  0]

            sage: S = ClusterSeed(QuiverMutationType([['A',1],['A',3]]))
            sage: S.b_matrix()
            [ 0  0  0  0]
            [ 0  0  1  0]
            [ 0 -1  0 -1]
            [ 0  0  1  0]

            sage: T = S.mutate(0,inplace=False)
            sage: S == T
            False
        """
        if inplace:
            seed = self
        else:
            seed = ClusterSeed( self )

        n, m = seed._n, seed._m
        V = range(n)

        if sequence in V:
            seq = [sequence]
        else:
            seq = sequence
        if type( seq ) is tuple:
            seq = list( seq )
        if not type( seq ) is list:
            raise ValueError, 'The quiver can only be mutated at a vertex or at a sequence of vertices'
        if not type(inplace) is bool:
            raise ValueError, 'The second parameter must be boolean.  To mutate at a sequence of length 2, input it as a list.'
        if any( v not in V for v in seq ):
            v = filter( lambda v: v not in V, seq )[0]
            raise ValueError, 'The quiver cannot be mutated at the vertex ' + str( v )

        for k in seq:
            M = seed._M
            cluster = seed._cluster
            mon_p = seed._R(1)
            mon_n = seed._R(1)

            for j in range(n+m):
                if M[j,k] > 0:
                    mon_p = mon_p*cluster[j]**M[j,k]
                elif M[j,k] < 0:
                    mon_n = mon_n*cluster[j]**(-M[j,k])

            cluster[k] = (mon_p+mon_n)*cluster[k]**(-1)
            seed._M.mutate(k)
            #seed._M = _matrix_mutate( seed._M, k )

        seed._quiver = None
        if not inplace:
            return seed

    def mutation_sequence(self, sequence, show_sequence=False, fig_size=1.2,return_output='seed'):
        r"""
        Returns the seeds obtained by mutating ``self`` at all vertices in ``sequence``.

        INPUT:

        - ``sequence`` -- an iterable of vertices of self.
        - ``show_sequence`` -- (default: False) if True, a png containing the associated quivers is shown.
        - ``fig_size`` -- (default: 1.2) factor by which the size of the plot is multiplied.
        - ``return_output`` -- (default: 'seed') determines what output is to be returned::

            * if 'seed', outputs all the cluster seeds obtained by the ``sequence`` of mutations.
            * if 'matrix', outputs a list of exchange matrices.
            * if 'var', outputs a list of new cluster variables obtained at each step.

        EXAMPLES::

            sage: S = ClusterSeed(['A',2])
            sage: for T in S.mutation_sequence([0,1,0]):
            ...     print T.b_matrix()
            [ 0 -1]
            [ 1  0]
            [ 0  1]
            [-1  0]
            [ 0 -1]
            [ 1  0]
        """
        seed = ClusterSeed( self )
        n = seed._n
        m = seed._m

        new_clust_var = []
        seed_sequence = []

        for v in sequence:
            seed = seed.mutate(v,inplace=False)
            new_clust_var.append( seed._cluster[v])
            seed_sequence.append( seed )

        if show_sequence:
            self.quiver().mutation_sequence(sequence=sequence, show_sequence=True, fig_size=fig_size )

        if return_output=='seed':
            return seed_sequence
        elif return_output=='matrix':
            return [ seed._M for seed in seed_sequence ]
        elif return_output=='var':
            return new_clust_var
        else:
            raise ValueError, 'The parameter `return_output` can only be `seed`, `matrix`, or `var`.'

    def exchangeable_part(self):
        r"""
        Returns the restriction to the principal part (i.e. the exchangeable variables) of ``self``.

        EXAMPLES::

            sage: S = ClusterSeed(['A',4])
            sage: T = ClusterSeed( S.quiver().digraph().edges(), frozen=1 )
            sage: T.quiver().digraph().edges()
            [(0, 1, (1, -1)), (2, 1, (1, -1)), (2, 3, (1, -1))]

            sage: T.exchangeable_part().quiver().digraph().edges()
            [(0, 1, (1, -1)), (2, 1, (1, -1))]

            sage: S2 = S.principal_extension()
            sage: S3 = S2.principal_extension(ignore_coefficients=True)
            sage: S2.exchangeable_part() == S3.exchangeable_part()
            True
        """
        from sage.combinat.cluster_algebra_quiver.mutation_class import _principal_part
        eval_dict = dict( [ ( self.y(i), 1 ) for i in xrange(self._m) ] )
        seed = ClusterSeed( _principal_part( self._M ) )
        seed._cluster = [ self._cluster[k].subs(eval_dict) for k in xrange(self._n) ]
        seed._mutation_type = self._mutation_type
        return seed

    def principal_extension(self,ignore_coefficients=False):
        r"""
        Returns the principal extension of self, adding n frozen variables to any previously frozen variables. I.e., the seed obtained by adding a frozen variable to every exchangeable variable of ``self``.

        EXAMPLES::

            sage: S = ClusterSeed([[0,1],[1,2],[2,3],[2,4]]); S
            A seed for a cluster algebra of rank 5

            sage: T = S.principal_extension(); T
            A seed for a cluster algebra of rank 5 with 5 frozen variables

            sage: T.b_matrix()
            [ 0  1  0  0  0]
            [-1  0  1  0  0]
            [ 0 -1  0  1  1]
            [ 0  0 -1  0  0]
            [ 0  0 -1  0  0]
            [ 1  0  0  0  0]
            [ 0  1  0  0  0]
            [ 0  0  1  0  0]
            [ 0  0  0  1  0]
            [ 0  0  0  0  1]

            sage: T2 = T.principal_extension()
            Traceback (most recent call last):
            ...
            ValueError: The b-matrix is not square. Use ignore_coefficients to ignore this.

            sage: T2 = T.principal_extension(ignore_coefficients=True); T2.b_matrix()
            [ 0  1  0  0  0]
            [-1  0  1  0  0]
            [ 0 -1  0  1  1]
            [ 0  0 -1  0  0]
            [ 0  0 -1  0  0]
            [ 1  0  0  0  0]
            [ 0  1  0  0  0]
            [ 0  0  1  0  0]
            [ 0  0  0  1  0]
            [ 0  0  0  0  1]
            [ 1  0  0  0  0]
            [ 0  1  0  0  0]
            [ 0  0  1  0  0]
            [ 0  0  0  1  0]
            [ 0  0  0  0  1]
            """
        from sage.matrix.all import identity_matrix
        if not ignore_coefficients and self._m != 0:
            raise ValueError("The b-matrix is not square. Use ignore_coefficients to ignore this.")
        M = self._M.stack(identity_matrix(self._n))
        is_principal = (self._m == 0)
        seed = ClusterSeed( M, is_principal=is_principal )
        seed._mutation_type = self._mutation_type
        return seed

    def reorient( self, data ):
        r"""
        Reorients ``self`` with respect to the given total order,
        or with respect to an iterator of ordered pairs.

        WARNING:

        - This operation might change the mutation type of ``self``.
        - Ignores ordered pairs `(i,j)` for which neither `(i,j)` nor `(j,i)` is an edge of ``self``.

        INPUT:

        - ``data`` -- an iterator defining a total order on ``self.vertices()``, or an iterator of ordered pairs in ``self`` defining the new orientation of these edges.

        EXAMPLES::

            sage: S = ClusterSeed(['A',[2,3],1])

            sage: S.reorient([(0,1),(2,3)])

            sage: S.reorient([(1,0),(2,3)])

            sage: S.reorient([0,1,2,3,4])
        """
        if not self._quiver:
            self.quiver()
        self._quiver.reorient( data )
        self._M = self._quiver._M
        self.reset_cluster()
        self._mutation_type = None

    def set_cluster( self, cluster ):
        r"""
        Sets the cluster for ``self`` to ``cluster``.

        INPUT:

        - ``cluster`` -- an iterable defining a cluster for ``self``.

        EXAMPLES::

            sage: S = ClusterSeed(['A',3])
            sage: cluster = S.cluster()
            sage: S.mutate([1,2,1])
            sage: S.cluster()
            [x0, (x1 + 1)/x2, (x0*x2 + x1 + 1)/(x1*x2)]

            sage: S.set_cluster(cluster)
            sage: S.cluster()
            [x0, x1, x2]
        """
        if not len(cluster) == self._n+self._m:
            raise ValueError('The number of given cluster variables is wrong')
        if any(c not in self._R for c in cluster):
            raise ValueError('The cluster variables are not all contained in %s'%self._R)
        self._cluster = [ self._R(x) for x in cluster ]
        self._is_principal = None

    def reset_cluster( self ):
        r"""
        Resets the cluster of ``self`` to the initial cluster.

        EXAMPLES::

            sage: S = ClusterSeed(['A',3])
            sage: S.mutate([1,2,1])
            sage: S.cluster()
            [x0, (x1 + 1)/x2, (x0*x2 + x1 + 1)/(x1*x2)]

            sage: S.reset_cluster()
            sage: S.cluster()
            [x0, x1, x2]

            sage: T = S.principal_extension()
            sage: T.cluster()
            [x0, x1, x2]
            sage: T.mutate([1,2,1])
            sage: T.cluster()
            [x0, (x1*y2 + x0)/x2, (x1*y1*y2 + x0*y1 + x2)/(x1*x2)]

            sage: T.reset_cluster()
            sage: T.cluster()
            [x0, x1, x2]
        """
        self.set_cluster(self._R.gens())

    def reset_principal_coefficients( self ):
        r"""
        Resets the coefficients of ``self`` to the frozen variables.

        EXAMPLES::

            sage: S = ClusterSeed(['A',3]).principal_extension()
            sage: S.b_matrix()
            [ 0  1  0]
            [-1  0 -1]
            [ 0  1  0]
            [ 1  0  0]
            [ 0  1  0]
            [ 0  0  1]
            sage: S.mutate([1,2,1])
            sage: S.b_matrix()
            [ 0  1 -1]
            [-1  0  1]
            [ 1 -1  0]
            [ 1  0  0]
            [ 0  1 -1]
            [ 0  0 -1]
            sage: S.reset_principal_coefficients()
            sage: S.b_matrix()
            [ 0  1 -1]
            [-1  0  1]
            [ 1 -1  0]
            [ 1  0  0]
            [ 0  1  0]
            [ 0  0  1]
        """
        n,m = self._n, self._m
        if not n == m:
            raise ValueError("The numbers of cluster variables and of frozen variables do not coincide.")
        for i in xrange(m):
            for j in xrange(n):
                if i == j:
                    self._M[i+n,j] = 1
                else:
                    self._M[i+n,j] = 0
        self._quiver = None

class ClusterVariable(FractionFieldElement):
    r"""
    This class is a thin wrapper for cluster variables in cluster seeds.

    It provides the extra feature to store if a variable is frozen or not.
    """
    def __init__( self, parent, numerator, denominator, coerce=True, reduce=True, variable_type=None ):
        r"""
        Initializes a cluster variable in the same way that elements in the field of rational functions are initialized.

        .. see also:: :class:`Fraction Field of Multivariate Polynomial Ring`

        TESTS::

            sage: S = ClusterSeed(['A',2])
            sage: for f in S.cluster():
            ...     print type(f)
            <class 'sage.combinat.cluster_algebra_quiver.cluster_seed.ClusterVariable'>
            <class 'sage.combinat.cluster_algebra_quiver.cluster_seed.ClusterVariable'>
        """
        FractionFieldElement.__init__( self, parent, numerator, denominator, coerce=coerce, reduce=reduce )
        self._variable_type = variable_type
