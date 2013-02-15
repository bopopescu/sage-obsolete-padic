"""
p-Adic Capped Relative Elements

Elements of p-Adic Rings with Capped Relative Precision



AUTHORS:

- David Roe: initial version, rewriting to use templates (2012-3-1)
- Genya Zaytman: documentation
- David Harvey: doctests
"""

#*****************************************************************************
#       Copyright (C) 2007-2013 David Roe <roed.math@gmail.com>
#                               William Stein <wstein@gmail.com>
#
#  Distributed under the terms of the GNU General Public License (GPL)
#  as published by the Free Software Foundation; either version 2 of
#  the License, or (at your option) any later version.
#
#                  http://www.gnu.org/licenses/
#*****************************************************************************

include "../../libs/linkages/padics/mpz.pxi"
include "CR_template.pxi"

from sage.libs.pari.gen cimport PariInstance
cdef PariInstance P = sage.libs.pari.all.pari
from sage.rings.finite_rings.integer_mod import Mod

cdef class pAdicCappedRelativeElement(CRElement):
    """
    Constructs new element with given parent and value.

    INPUT:

    - ``x`` -- value to coerce into a capped relative ring or field

    - ``absprec`` -- maximum number of digits of absolute precision

    - ``relprec`` -- maximum number of digits of relative precision

    EXAMPLES::

        sage: R = Zp(5, 10, 'capped-rel')

    Construct from integers::

        sage: R(3)
        3 + O(5^10)
        sage: R(75)
        3*5^2 + O(5^12)
        sage: R(0)
        0
        sage: R(-1)
        4 + 4*5 + 4*5^2 + 4*5^3 + 4*5^4 + 4*5^5 + 4*5^6 + 4*5^7 + 4*5^8 + 4*5^9 + O(5^10)
        sage: R(-5)
        4*5 + 4*5^2 + 4*5^3 + 4*5^4 + 4*5^5 + 4*5^6 + 4*5^7 + 4*5^8 + 4*5^9 + 4*5^10 + O(5^11)
        sage: R(-7*25)
        3*5^2 + 3*5^3 + 4*5^4 + 4*5^5 + 4*5^6 + 4*5^7 + 4*5^8 + 4*5^9 + 4*5^10 + 4*5^11 + O(5^12)

    Construct from rationals::

        sage: R(1/2)
        3 + 2*5 + 2*5^2 + 2*5^3 + 2*5^4 + 2*5^5 + 2*5^6 + 2*5^7 + 2*5^8 + 2*5^9 + O(5^10)
        sage: R(-7875/874)
        3*5^3 + 2*5^4 + 2*5^5 + 5^6 + 3*5^7 + 2*5^8 + 3*5^10 + 3*5^11 + 3*5^12 + O(5^13)
        sage: R(15/425)
        Traceback (most recent call last):
        ...
        ValueError: p divides the denominator

    Construct from IntegerMod::

        sage: R(Integers(125)(3))
        3 + O(5^3)
        sage: R(Integers(5)(3))
        3 + O(5)
        sage: R(Integers(5^30)(3))
        3 + O(5^10)
        sage: R(Integers(5^30)(1+5^23))
        1 + O(5^10)
        sage: R(Integers(49)(3))
        Traceback (most recent call last):
        ...
        TypeError: cannot coerce from the given integer mod ring (not a power of the same prime)

    ::

        sage: R(Integers(48)(3))
        Traceback (most recent call last):
        ...
        TypeError: cannot coerce from the given integer mod ring (not a power of the same prime)

    Some other conversions::

        sage: R(R(5))
        5 + O(5^11)

    Construct from Pari objects::

        sage: R = Zp(5)
        sage: x = pari(123123) ; R(x)
        3 + 4*5 + 4*5^2 + 4*5^3 + 5^4 + 4*5^5 + 2*5^6 + 5^7 + O(5^20)
        sage: R(pari(R(5252)))
        2 + 2*5^3 + 3*5^4 + 5^5 + O(5^20)
        sage: R = Zp(5,prec=5)
        sage: R(pari(-1))
        4 + 4*5 + 4*5^2 + 4*5^3 + 4*5^4 + O(5^5)
        sage: pari(R(-1))
        4 + 4*5 + 4*5^2 + 4*5^3 + 4*5^4 + O(5^5)
        sage: pari(R(0))
        0
        sage: R(pari(R(0,5)))
        O(5^5)

    # todo: doctests for converting from other types of p-adic rings
    """
    def lift(self):
        """
        Return an integer or rational congruent to self modulo self's
        precision.  If a rational is returned, its denominator will
        eqaul p^ordp(self).

        EXAMPLES::

            sage: R = Zp(7,4,'capped-rel'); a = R(8); a.lift()
            8
            sage: R = Qp(7,4); a = R(8); a.lift()
            8
            sage: R = Qp(7,4); a = R(8/7); a.lift()
            8/7
        """
        return self.lift_c()

    cdef lift_c(self):
        """
        Implementation of lift.

        TESTS::

            sage: O(5^5).lift() #indirect doctest
            0
            sage: R = Qp(5); R(0).lift()
            0
            sage: R(5/9).lift()
            264909532335070
            sage: R(9/5).lift()
            9/5
        """
        cdef Integer ans
        cdef Rational ansr
        if self.ordp >= 0:
            ans = PY_NEW(Integer)
            if self.relprec == 0:
                mpz_set_ui(ans.value, 0)
            else:
                mpz_set(ans.value, self.unit)
                mpz_mul(ans.value, ans.value, self.prime_pow.pow_mpz_t_tmp(self.ordp)[0])
            return ans
        else:
            ansr = PY_NEW(Rational)
            if self.relprec == 0:
                mpq_set_si(ansr.value, 0, 1)
            else:
                mpz_set(mpq_numref(ansr.value), self.unit)
                mpz_set(mpq_denref(ansr.value), self.prime_pow.pow_mpz_t_tmp(-self.ordp)[0])
            return ansr

    def _pari_(self):
        """
        Converts this element to an equivalent pari element.

        EXAMPLES::

            sage: R = Zp(17, 10); a = ~R(14); pari(a) #indirect doctest
            11 + 3*17 + 17^2 + 6*17^3 + 13*17^4 + 15*17^5 + 10*17^6 + 3*17^7 + 17^8 + 6*17^9 + O(17^10)
            sage: pari(R(0))
            0
            sage: pari(R(0,5))
            O(17^5)
        """
        return self._to_gen()

    cdef pari_gen _to_gen(self):
        """
        Converts this element to an equivalent pari element.

        EXAMPLES::

           sage: R = Zp(5, 10); a = R(17); pari(a) #indirect doctest
           2 + 3*5 + O(5^10)
           sage: pari(R(0))
           0
           sage: pari(R(0,5))
           O(5^5)
        """
        if exactzero(self.ordp):
            return P.new_gen_from_int(0)
        else:
            return P.new_gen_from_padic(self.ordp, self.relprec,
                                        self.prime_pow.prime.value,
                                        self.prime_pow.pow_mpz_t_tmp(self.relprec)[0],
                                        self.unit)
    def _integer_(self, Z=None):
        """
        Returns an integer congruent to this element modulo
        ``p^self.absolute_precision()``.

         EXAMPLES::

            sage: R = Zp(5); a = R(-1); a._integer_()
            95367431640624
         """
        if self.ordp < 0:
            raise ValueError, "Cannot form an integer out of a p-adic field element with negative valuation"
        return self.lift_c()

    def residue(self, absprec=1):
        """
        Reduces this element modulo `p^{\mbox{absprec}}`.

        INPUT:

        - absprec - an integer (defaults to 1)

        OUTPUT:

        Element of `\ZZ/(p^{\mbox{absprec}} \ZZ)` -- the reduction modulo `p^{\mbox{absprec}}`

        EXAMPLES::

            sage: R = Zp(7,4,'capped-rel'); a = R(8); a.residue(1)
            1
            sage: R = Qp(7,4,'capped-rel'); a = R(8); a.residue(1)
            1
            sage: a.residue(6)
            Traceback (most recent call last):
            ...
            PrecisionError: Not enough precision known in order to compute residue.
            sage: b = a/7
            sage: b.residue(1)
            Traceback (most recent call last):
            ...
            ValueError: Element must have non-negative valuation in order to compute residue.
        """
        cdef Integer selfvalue, modulus
        cdef long aprec
        if not PY_TYPE_CHECK(absprec, Integer):
            absprec = Integer(absprec)
        if absprec > self.precision_absolute():
            raise PrecisionError, "Not enough precision known in order to compute residue."
        elif absprec < 0:
            raise ValueError, "cannot reduce modulo a negative power of p"
        aprec = mpz_get_ui((<Integer>absprec).value)
        if self.ordp < 0:
            raise ValueError, "Element must have non-negative valuation in order to compute residue."
        modulus = PY_NEW(Integer)
        mpz_set(modulus.value, self.prime_pow.pow_mpz_t_tmp(aprec)[0])
        selfvalue = PY_NEW(Integer)
        if self.relprec == 0:
            mpz_set_ui(selfvalue.value, 0)
        else:
            # Need to do this better.
            mpz_mul(selfvalue.value, self.prime_pow.pow_mpz_t_tmp(self.ordp)[0], self.unit)
        return Mod(selfvalue, modulus)

def unpickle_pcre_v1(R, unit, ordp, relprec):
    """
    Unpickles a capped relative element.

    EXAMPLES::

        sage: from sage.rings.padics.padic_capped_relative_element import unpickle_pcre_v1
        sage: R = Zp(5)
        sage: a = unpickle_pcre_v1(R, 17, 2, 5); a
        2*5^2 + 3*5^3 + O(5^7)
    """
    return unpickle_cre_v2(pAdicCappedRelativeElement, R, unit, ordp, relprec)

def base_p_list(Integer n, bint pos, PowComputer_class prime_pow):
    """
    Returns a base-p list of digits of ``n``.

    INPUT:

    - ``n`` -- a positive Integer.

    - ``pos`` -- a boolean.  If True, then returns the standard base `p` expansion.
                 Otherwise, the digits lie in the range `-p/2` to `p/2`.

    - ``prime_pow`` -- A PowComputer giving the prime.

    EXAMPLES::

        sage: from sage.rings.padics.padic_capped_relative_element import base_p_list
        sage: base_p_list(192837, True, Zp(5).prime_pow)
        [2, 2, 3, 2, 3, 1, 2, 2]
        sage: 2 + 2*5 + 3*5^2 + 2*5^3 + 3*5^4 + 5^5 + 2*5^6 + 2*5^7
        192837
        sage: base_p_list(192837, False, Zp(5).prime_pow)
        [2, 2, -2, -2, -1, 2, 2, 2]
        sage: 2 + 2*5 - 2*5^2 - 2*5^3 - 5^4 + 2*5^5 + 2*5^6 + 2*5^7
        192837
    """
    if mpz_sgn(n.value) < 0:
        raise ValueError("n must be nonnegative")
    return clist(n.value, prime_pow.prec_cap, pos, prime_pow)
