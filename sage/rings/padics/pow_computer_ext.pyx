"""
The classes in this file are designed to be attached to p-adic parents and elements for cython access to properties of the parent.
In addition to storing the defining polynomial (as an NTL polynomial) at different precisions, they also cache powers of p
and data to speed right shifting of elements.
The heirarchy of PowComputers splits first at whether it's for a base ring (Qp or Zp) or an extension.
Among the extension classes (those in this file), they are first split by the type of NTL polynomial
(ntl_ZZ_pX or ntl_ZZ_pEX), then by the amount and style of caching (see below).  Finally,
there are subclasses of the ntl_ZZ_pX PowComputers that cache additional information for Eisenstein extensions.

There are three styles of caching:
FM: caches powers of p up to the cache_limit, only caches the polynomial modulus and the ntl_ZZ_pContext of precision prec_cap.
small: Requires cache_limit = prec_cap.  Caches p^k for every k up to the cache_limit and caches a polynomial modulus and a ntl_ZZ_pContext
for each such power of p.
big: Caches as the small does up to cache_limit and caches prec_cap.  Also has a dictionary that caches values above the cache_limit when they
are computed (rather than at ring creation time).

EXAMPLES:

AUTHORS:
    -- David Roe  (2008-01-01) initial version
"""

#*****************************************************************************
#       Copyright (C) 2008 David Roe <roed@math.harvard.edu>
#                          William Stein <wstein@gmail.com>
#
#  Distributed under the terms of the GNU General Public License (GPL)
#
#                  http://www.gnu.org/licenses/
#*****************************************************************************

include "../../ext/gmp.pxi"
include "../../ext/interrupt.pxi"
include "../../ext/stdsage.pxi"
include "../../ext/python_list.pxi"
include "../../ext/python_dict.pxi"

import weakref
from sage.misc.misc import cputime
from sage.rings.infinity import infinity
from sage.libs.ntl.ntl_ZZ_pContext cimport ntl_ZZ_pContext_factory
from sage.libs.ntl.ntl_ZZ_pContext import ZZ_pContext_factory
from sage.libs.ntl.ntl_ZZ cimport ntl_ZZ
from sage.libs.ntl.ntl_ZZ_pX cimport ntl_ZZ_pX, ntl_ZZ_pX_Modulus
from sage.rings.integer cimport Integer

cdef int ZZ_pX_Eis_init(PowComputer_ZZ_pX prime_pow, ntl_ZZ_pX shift_seed) except -1:
    """
    Precomputes quantities for shifting right in Eisenstein extensions.

    INPUT:
    prime_pow -- the PowComputer to be initialized
    shift_seed -- x^e/p as a polynomial of degree at most e-1 in x.
    """
    if prime_pow.deg <= 1:
        raise ValueError, "Eisenstein extension must have degree at least 2"
    cdef unsigned long D = prime_pow.deg - 1
    cdef int low_length = 0
    cdef int high_length = 0
    if sizeof(long) > 4 and D > 4294967295: # 2^32 - 1
        low_length += 32
        D = D >> 32
    if D >= 65536: # 2^16
        low_length += 16
        D = D >> 16
    if D >= 256: # 2^8
        low_length += 8
        D = D >> 8
    if D >= 16: # 2^4
        low_length += 4
        D = D >> 4
    if D >= 4: # 2^2
        low_length += 2
        D = D >> 2
    if D >= 2: # 2^1
        low_length += 1
        D = D >> 1
    low_length += 1
    # low_length is the number of elements in the list we need to store.
    # if deg = 2, low_length = 1 (store p/x)
    # if deg = 3,4, low_length = 2 (store p/x, p/x^2)
    # if deg = 5,6,7,8, low_length = 3 (store p/x, p/x^2, p/x^4)
    # if deg = 9,...,16, low_length = 4 (store p/x, p/x^2, p/x^4, p/x^8)

    # Now we do the same process for powers of p, ie storing p^(2^k)/x^(e*2^k)
    D = prime_pow.prec_cap - 1
    high_length = 0
    if sizeof(long) > 4 and D > 4294967295: # 2^32 - 1
        high_length += 32
        D = D >> 32
    if D >= 65536: # 2^16
        high_length += 16
        D = D >> 16
    if D >= 256: # 2^8
        high_length += 8
        D = D >> 8
    if D >= 16: # 2^4
        high_length += 4
        D = D >> 4
    if D >= 4: # 2^2
        high_length += 2
        D = D >> 2
    if D >= 2: # 2^1
        high_length += 1
        D = D >> 1
    high_length += 1
    # high_length is the number of elements in the list we need to store.
    # if prec_cap = 2, high_length = 1 (store p/x^e)
    # if prec_cap = 3,4, high_length = 2 (store p/x^e, p^2/x^(2e))
    # if prec_cap = 5,6,7,8, high_length = 3 (store p/x^e, p^2/x^(2e), p^4/x^(4e))
    # if prec_cap = 9,...,16, high_length = 4 (store p/x, p^2/x^(2e), p^4/x^(4e), p^8/x^(8e))

    cdef ZZ_pX_Multiplier_c* low_shifter_m
    cdef ZZ_pX_Multiplier_c* high_shifter_m
    cdef ZZ_pX_c* low_shifter_p
    cdef ZZ_pX_c* high_shifter_p
    cdef bint multiplier
    if PY_TYPE_CHECK(prime_pow, PowComputer_ZZ_pX_FM_Eis):
        multiplier = 1
        (<PowComputer_ZZ_pX_FM_Eis>prime_pow).low_length = low_length
        (<PowComputer_ZZ_pX_FM_Eis>prime_pow).high_length = high_length

        _sig_on
        (<PowComputer_ZZ_pX_FM_Eis>prime_pow).low_shifter = <ZZ_pX_Multiplier_c *>sage_malloc(sizeof(ZZ_pX_Multiplier_c) * low_length)
        (<PowComputer_ZZ_pX_FM_Eis>prime_pow).high_shifter = <ZZ_pX_Multiplier_c *>sage_malloc(sizeof(ZZ_pX_Multiplier_c) * high_length)
        _sig_off
        low_shifter_m = (<PowComputer_ZZ_pX_FM_Eis>prime_pow).low_shifter
        high_shifter_m = (<PowComputer_ZZ_pX_FM_Eis>prime_pow).high_shifter
    elif PY_TYPE_CHECK(prime_pow, PowComputer_ZZ_pX_small_Eis):
        multiplier = 0
        (<PowComputer_ZZ_pX_small_Eis>prime_pow).low_length = low_length
        (<PowComputer_ZZ_pX_small_Eis>prime_pow).high_length = high_length

        _sig_on
        (<PowComputer_ZZ_pX_small_Eis>prime_pow).low_shifter = <ZZ_pX_c *>sage_malloc(sizeof(ZZ_pX_c) * low_length)
        (<PowComputer_ZZ_pX_small_Eis>prime_pow).high_shifter = <ZZ_pX_c *>sage_malloc(sizeof(ZZ_pX_c) * high_length)
        _sig_off
        low_shifter_p = (<PowComputer_ZZ_pX_small_Eis>prime_pow).low_shifter
        high_shifter_p = (<PowComputer_ZZ_pX_small_Eis>prime_pow).high_shifter
    elif PY_TYPE_CHECK(prime_pow, PowComputer_ZZ_pX_big_Eis):
        multiplier = 0
        (<PowComputer_ZZ_pX_big_Eis>prime_pow).low_length = low_length
        (<PowComputer_ZZ_pX_big_Eis>prime_pow).high_length = high_length

        _sig_on
        (<PowComputer_ZZ_pX_big_Eis>prime_pow).low_shifter = <ZZ_pX_c *>sage_malloc(sizeof(ZZ_pX_c) * low_length)
        (<PowComputer_ZZ_pX_big_Eis>prime_pow).high_shifter = <ZZ_pX_c *>sage_malloc(sizeof(ZZ_pX_c) * high_length)
        _sig_off
        low_shifter_p = (<PowComputer_ZZ_pX_big_Eis>prime_pow).low_shifter
        high_shifter_p = (<PowComputer_ZZ_pX_big_Eis>prime_pow).high_shifter
    else:
        raise RuntimeError, "unrecognized Eisenstein type"
        
    cdef long i
    cdef ZZ_pX_c tmp, modup, into_multiplier, shift_seed_inv
    cdef ZZ_c a
    # We obtain successive p/x^(2^i) by squaring and then dividing by p.  So we need one extra digit of precision.
    prime_pow.restore_top_context()
    #cdef ntl_ZZ_pContext_class cup = prime_pow.get_context(prime_pow.prec_cap + low_length)
    #cup.restore_c()
    #ZZ_pX_conv_modulus(modup, prime_pow.get_top_modulus()[0].val(), cup.x)
    #ZZ_div(a, ZZ_p_rep(ZZ_pX_ConstTerm(modup)), prime_pow.small_powers[1])
    #ZZ_InvMod(a, a, prime_pow.pow_ZZ_tmp(prime_pow.prec_cap + low_length)[0])
    #ZZ_negate(a, a)
    ##cdef ntl_ZZ_pX printer = ntl_ZZ_pX([],prime_pow.get_context(prime_pow.prec_cap))
    ##printer.x = modup
    ##print printer
    # Note that we're losing one digit of precision here.
    # This is correct because right shifting does not preserve precision.
    # a is now the negative of the inverse of the unit part of the constant of the defining polynomial (there's a mouthful)
    #ZZ_pX_RightShift(tmp, modup, 1)
    ##printer.x = modup
    ##print printer
    #ZZ_pX_mul_ZZ_p(tmp, tmp, ZZ_to_ZZ_p(a))
    # tmp is now p/x
    #ZZ_pX_conv_modulus(into_multiplier, tmp, prime_pow.get_top_context().x)
    ##printer.x = into_multiplier
    ##print printer
    #if multiplier:
    #    ZZ_pX_Multiplier_construct(low_shifter_m)
    #    ZZ_pX_Multiplier_build(low_shifter_m[0], into_multiplier, prime_pow.get_top_modulus()[0])
    #else:
    #    ZZ_pX_construct(low_shifter_p)
    #    low_shifter_p[0] = into_multiplier
    ##printer.x = (low_shifter[0]).val()
    ##print printer
    ZZ_pX_InvMod_newton_ram(shift_seed_inv, shift_seed.x, prime_pow.get_top_modulus()[0], prime_pow.get_top_context().x)
    for i from 0 <= i < low_length:
        # Currently tmp = p / x^(2^(i-1)).  Squaring yields p^2 / x^(2^i)
        #ZZ_pX_SqrMod(tmp, tmp, modup)
        # Now we divide by p.
        #ZZ_pX_right_pshift(tmp, tmp, prime_pow.small_powers[1], cup.x)
        #ZZ_pX_conv_modulus(into_multiplier, tmp, prime_pow.get_top_context().x)
        ZZ_pX_PowerXMod_long_pre(into_multiplier, prime_pow.e - (1L << i), prime_pow.get_top_modulus()[0])
        ZZ_pX_MulMod_pre(into_multiplier, into_multiplier, shift_seed_inv, prime_pow.get_top_modulus()[0])
        ##printer.x = into_multiplier
        ##print printer
        if multiplier:
            ZZ_pX_Multiplier_construct(&(low_shifter_m[i]))
            ZZ_pX_Multiplier_build(low_shifter_m[i], into_multiplier, prime_pow.get_top_modulus()[0])
        else:
            ZZ_pX_construct(&(low_shifter_p[i]))
            low_shifter_p[i] = into_multiplier

    # Now we handle high_shifter.
    # We can obtain p/x^e by computing the inverse of x^e/p.
    # Note that modup is still defined from before
    ###cup.restore_c()

    ###ZZ_pX_conv_modulus(modup, prime_pow.get_top_modulus()[0].val(), cup.x)
    ###ZZ_pX_SetCoeff_long(modup, prime_pow.deg, 0)
    ###ZZ_pX_negate(modup, modup)
    ###ZZ_pX_right_pshift(into_multiplier, modup, prime_pow.small_powers[1], prime_pow.get_top_context().x)

    ###printer.x = into_multiplier
    ###print printer

    # into_multiplier now holds x^e/p
    # prime_pow.c.x should have been restored, but we make sure
    prime_pow.restore_top_context()
    ##print "shift_seed=%s"%shift_seed
    ##printer.x = prime_pow.get_top_modulus()[0].val()
    ##print "top_modulus=%s"%printer
    ##print "top_context=%s"%prime_pow.get_top_context()
    into_multiplier = shift_seed_inv
    #ZZ_pX_InvMod_newton_ram(into_multiplier, shift_seed.x, prime_pow.get_top_modulus()[0], prime_pow.get_top_context().x)
    ##printer.x = into_multiplier
    ##print "inverse = %s"%printer
    ##ZZ_pX_MulMod_pre(printer.x, into_multiplier, shift_seed.x, prime_pow.get_top_modulus()[0])
    ##print "product = %s"%printer
    if multiplier:
        ZZ_pX_Multiplier_construct(high_shifter_m)
        ZZ_pX_Multiplier_build(high_shifter_m[0], into_multiplier, prime_pow.get_top_modulus()[0])
    else:
        ZZ_pX_construct(high_shifter_p)
        high_shifter_p[0] = into_multiplier
    # Now we cache powers of p/x^e.  This is a unit, so we don't have to worry about precision issues (yay!)
    for i from 1 <= i < high_length:
        ZZ_pX_SqrMod_pre(into_multiplier, into_multiplier, prime_pow.get_top_modulus()[0])
        if multiplier:
            ZZ_pX_Multiplier_construct(&(high_shifter_m[i]))
            ZZ_pX_Multiplier_build(high_shifter_m[i], into_multiplier, prime_pow.get_top_modulus()[0])
        else:
            ZZ_pX_construct(&(high_shifter_p[i]))
            high_shifter_p[i] = into_multiplier

cdef int ZZ_pX_eis_shift(PowComputer_ZZ_pX self, ZZ_pX_c* x, ZZ_pX_c* a, long n, long finalprec) except -1:
    ##print "starting..."
    cdef ZZ_pX_c low_part
    cdef ZZ_pX_c shifted_high_part
    cdef ZZ_pX_c powerx
    cdef ZZ_pX_c shifter
    cdef ZZ_pX_c lowshift
    cdef ZZ_pX_c highshift
    cdef ZZ_pX_c working, working2
    cdef ntl_ZZ_pContext_class c
    cdef ZZ_pX_Modulus_c* m
    cdef long pshift = n / self.e
    cdef long eis_part = n % self.e
    cdef long two_shift = 1
    cdef int i
    cdef ZZ_pX_c* high_shifter
    cdef ZZ_pX_c* low_shifter
    cdef ZZ_pX_Multiplier_c* high_shifter_fm
    cdef ZZ_pX_Multiplier_c* low_shifter_fm
    cdef bint fm
    cdef long high_length
    if PY_TYPE_CHECK(self, PowComputer_ZZ_pX_small_Eis):
        high_shifter = (<PowComputer_ZZ_pX_small_Eis>self).high_shifter
        low_shifter = (<PowComputer_ZZ_pX_small_Eis>self).low_shifter
        high_length = (<PowComputer_ZZ_pX_small_Eis>self).high_length
        fm = False
    elif PY_TYPE_CHECK(self, PowComputer_ZZ_pX_big_Eis):
        high_shifter = (<PowComputer_ZZ_pX_big_Eis>self).high_shifter
        low_shifter = (<PowComputer_ZZ_pX_big_Eis>self).low_shifter
        high_length = (<PowComputer_ZZ_pX_big_Eis>self).high_length
        fm = False
    elif PY_TYPE_CHECK(self, PowComputer_ZZ_pX_FM_Eis):
        high_shifter_fm = (<PowComputer_ZZ_pX_FM_Eis>self).high_shifter
        low_shifter_fm = (<PowComputer_ZZ_pX_FM_Eis>self).low_shifter
        high_length = (<PowComputer_ZZ_pX_FM_Eis>self).high_length
        fm = True
    else:
        raise RuntimeError, "inconsistent type"
    
    cdef ntl_ZZ_pX printer
    if n < 0:
        if fm:
            c = self.get_top_context()
            m = self.get_top_modulus()
        else:
            c = self.get_context(finalprec)
            m = self.get_modulus(finalprec)
        c.restore_c()
        ##printer = ntl_ZZ_pX([],c)
        ZZ_pX_PowerXMod_long_pre(powerx, -n, m[0])
        ##printer.x = powerx
        ##print printer
        ZZ_pX_conv_modulus(x[0], a[0], c.x)
        ZZ_pX_MulMod_pre(x[0], powerx, a[0], m[0])
        ##printer.x = x[0]
        ##print printer
        return 0
    elif n == 0:
        if x != a:
            if fm:
                c = self.get_top_context()
            else:
                c = self.get_context(finalprec)
            ZZ_pX_conv_modulus(x[0], a[0], c.x)
        return 0
    
    ##print "eis_part: %s" %(eis_part)
    ##print "pshift: %s"%(pshift)

# The following doesn't work, sadly.  It should be possible to precompute and do better than what I replace this code with.    
#    c = self.get_context(finalprec)
#    m = self.get_modulus(finalprec)[0]
#    printer = ntl_ZZ_pX([],c)
#    if pshift:
#        ZZ_pX_right_pshift(x[0], a[0], self.pow_ZZ_tmp(pshift)[0], c.x)
#    else:
#        ZZ_pX_conv_modulus(x[0], a[0], c.x)
#    ##printer.x = a[0]
#    ##print "beginning: a = %s"%(printer)
#    c.restore_c()
#    if pshift:
#        i = 0
#        # This line restores the top context
#        #ZZ_pX_right_pshift(x[0], x[0], self.pow_ZZ_tmp(pshift)[0], c.x)
#        ##printer.x = x[0]
#        ##print printer
#        if pshift >= self.prec_cap:
#            # shifter = p^(2^(high_length - 1))/x^(e*2^(high_length - 1))
#            ZZ_pX_conv_modulus(shifter, high_shifter[high_length-1], c.x)
#            ##printer.x = shifter
#            ##print printer
#            # if val = r + s * 2^(high_length - 1)
#            # then shifter = p^(s*2^(high_length - 1))/x^(e*s*2^(high_length - 1))
#            ZZ_pX_PowerMod_long_pre(shifter, shifter, (pshift / (1L << (high_length - 1))), m)
#            ##printer.x = shifter
#            ##print printer
#            ZZ_pX_MulMod_pre(x[0], x[0], shifter, m)
#            ##printer.x = shifter
#            ##print printer
#            # Now we only need to multiply self.unit by p^r/x^(e*r) where r < 2^(high_length - 1), which is tractible.
#            pshift = pshift % (1L << (high_length - 1))
#        while pshift > 0:
#            if pshift & 1:
#                ##print "pshift = %s"%pshift
#                ##printer.x = x[0]
#                ##print printer
#                ZZ_pX_conv_modulus(highshift, high_shifter[i], c.x)
#                ZZ_pX_MulMod_pre(x[0], x[0], highshift, m)
#            i += 1
#            pshift = pshift >> 1
    if fm:
        c = self.get_top_context()
        m = self.get_top_modulus()
    else:
        c = self.get_context(finalprec + pshift + 1)
    c.restore_c()
    ZZ_pX_conv_modulus(working, a[0], c.x)
    if pshift:
        while pshift > 0:
            pshift -= 1
            if fm:
                ZZ_pX_right_pshift(working, working, self.pow_ZZ_tmp(1)[0],c.x)
                ZZ_pX_MulMod_premul(working, working, high_shifter_fm[0], m[0])
            else:
                c = self.get_context(finalprec + pshift + 1)
                m = self.get_modulus(finalprec + pshift + 1)
                ZZ_pX_right_pshift(working, working, self.pow_ZZ_tmp(1)[0],c.x)
                ZZ_pX_conv_modulus(highshift, high_shifter[0], c.x)
                ZZ_pX_MulMod_pre(working, working, highshift, m[0])
    elif not fm:
        m = self.get_modulus(finalprec + 1)
    ZZ_pX_conv_modulus(working2, working, c.x)
    i = 0
    two_shift = 1
    while eis_part > 0:
        ##print "eis_part = %s"%(eis_part)
        if eis_part & 1:
            ##print "i = %s"%(i)
            ##print "two_shift = %s"%(two_shift)
            ##printer.x = working2
            ##print "working2 = %s"%(printer)
            ZZ_pX_RightShift(shifted_high_part, working2, two_shift)
            ##printer.x = shifted_high_part
            ##print "shifted_high_part = %s"%(printer)
            ZZ_pX_LeftShift(low_part, shifted_high_part, two_shift)
            ZZ_pX_sub(low_part, working2, low_part)
            ##printer.x = low_part
            ##print "low_part = %s"%(printer)
            ZZ_pX_right_pshift(low_part, low_part, self.pow_ZZ_tmp(1)[0], c.x)
            ##printer.x = low_part
            ##print "low_part = %s"%(printer)
            if fm:
                ZZ_pX_MulMod_premul(low_part, low_part, low_shifter_fm[i], m[0])
            else:
                ZZ_pX_conv_modulus(lowshift, low_shifter[i], c.x)
                ZZ_pX_MulMod_pre(low_part, low_part, lowshift, m[0])
            ##printer.x = low_part
            ##print "low_part = %s"%(printer)
            ZZ_pX_add(working2, low_part, shifted_high_part)
            ##printer.x = working2
            ##print "x = %s"%(printer)
        i += 1
        two_shift = two_shift << 1
        eis_part = eis_part >> 1
    c = self.get_context(finalprec)
    ZZ_pX_conv_modulus(x[0], working2, c.x)

cdef class PowComputer_ext(PowComputer_class):
    def __new__(self, Integer prime, long cache_limit, long prec_cap, long ram_prec_cap, bint in_field, poly, shift_seed=None):
        """
        Constructs the storage for powers of prime as ZZ_c's.

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 10, 10, 20, False, ntl.ZZ_pX([-5, 0, 1], 5^10), 'small', 'e',ntl.ZZ_pX([1],5^10)) #indirect doctest
        """
        self._initialized = 0
        _sig_on
        self.small_powers = <ZZ_c *>sage_malloc(sizeof(ZZ_c) * (cache_limit + 1))
        _sig_off
        if self.small_powers == NULL:
            raise MemoryError, "out of memory allocating power storing"
        ZZ_construct(&self.top_power)

        cdef Py_ssize_t i
        cdef Integer x

        ZZ_construct(self.small_powers)
        ZZ_conv_from_int(self.small_powers[0], 1)

        if cache_limit > 0:
            ZZ_construct(&(self.small_powers[1]))
            mpz_to_ZZ(&(self.small_powers[1]), &prime.value)
            
        _sig_on
        for i from 2 <= i <= cache_limit:
            ZZ_construct(&(self.small_powers[i]))
            ZZ_mul(self.small_powers[i], self.small_powers[i-1], self.small_powers[1])
        mpz_to_ZZ(&self.top_power, &prime.value)
        ZZ_power(self.top_power, self.top_power, prec_cap)
        _sig_off
        mpz_init(self.temp_m)
        ZZ_construct(&self.temp_z)

        self._poly = poly
        self._shift_seed = shift_seed

    def __dealloc__(self):
        """
        Frees allocated memory.

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 5, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: del PC # indirect doctest
        """
        if (<PowComputer_class>self)._initialized:
            self.cleanup_ext()

    def __repr__(self):
        """
        Returns a string representation of self.

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 10, 10, 20, False, ntl.ZZ_pX([-5, 0, 1], 5^10), 'small', 'e',ntl.ZZ_pX([1],5^10))
        sage: PC # indirect doctest
        PowComputer_ext for 5, with polynomial [9765620 0 1]
        """
        return "PowComputer_ext for %s, with polynomial %s"%(self.prime, self.polynomial())

    def __reduce__(self):
        """
        For pickling.

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 10, 10, 20, False, ntl.ZZ_pX([-5, 0, 1], 5^10), 'small', 'e',ntl.ZZ_pX([1],5^10)); PC
        PowComputer_ext for 5, with polynomial [9765620 0 1]
        sage: loads(dumps(PC))
        PowComputer_ext for 5, with polynomial [9765620 0 1]
        """
        cdef Integer cache_limit, prec_cap, ram_prec_cap
        cache_limit = PY_NEW(Integer)
        mpz_set_si(cache_limit.value, self.cache_limit)
        prec_cap = PY_NEW(Integer)
        mpz_set_si(prec_cap.value, self.prec_cap)
        ram_prec_cap = PY_NEW(Integer)
        mpz_set_si(ram_prec_cap.value, self.ram_prec_cap)
        return PowComputer_ext_maker, (self.prime, cache_limit, prec_cap, ram_prec_cap, self.in_field, self._poly, self._prec_type, self._ext_type, self._shift_seed)

    cdef void cleanup_ext(self):
        """
        Frees memory allocated in PowComputer_ext.

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 5, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: del PC # indirect doctest
        """
        cdef Py_ssize_t i
        for i from 0 <= i <= self.cache_limit:
            ZZ_destruct(&(self.small_powers[i]))
        sage_free(self.small_powers)
        ZZ_destruct(&self.top_power)
        mpz_clear(self.temp_m)
        ZZ_destruct(&self.temp_z)
    
    cdef mpz_t* pow_mpz_t_tmp(self, long n):
        """
        Provides fast access to an mpz_t* pointing to self.prime^n.

        The location pointed to depends on the underlying representation.
        In no circumstances should you mpz_clear the result.
        The value pointed to may be an internal temporary variable for the class.
        In particular, you should not try to refer to the results of two
        pow_mpz_t_tmp calls at the same time, because the second
        call may overwrite the memory pointed to by the first.

        In the case of PowComputer_exts, the mpz_t pointed to will always
        be a temporary variable.

        See pow_mpz_t_tmp_demo for an example of this phenomenon.

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 10, 10, 20, False, ntl.ZZ_pX([-5, 0, 1], 5^10), 'small', 'e',ntl.ZZ_pX([1],5^10))
        sage: PC._pow_mpz_t_tmp_test(4) #indirect doctest
        625
        """
        # READ THE DOCSTRING
        if n < 0:
            raise ValueError, "n must be positive"
        if n <= self.cache_limit:
            ZZ_to_mpz(&self.temp_m, &(self.small_powers[n]))
        elif n == self.prec_cap:
            ZZ_to_mpz(&self.temp_m, &self.top_power)
        else:
            mpz_pow_ui(self.temp_m, self.prime.value, n)
        return &self.temp_m

    #def _pow_mpz_t_tmp_test(self, n):
    #    """
    #    Test for the pow_mpz_t_tmp function.  See that function's documentation for important warnings.
    #
    #    EXAMPLES:
    #    sage: PC = PowComputer_ext_maker(5, 10, 10, 20, False, ntl.ZZ_pX([-5, 0, 1], 5^10), 'small', 'e',ntl.ZZ_pX([1],5^10))
    #    sage: PC._pow_mpz_t_tmp_test(4) #indirect doctest
    #    625
    #    """
    #    cdef Integer _n = Integer(n)
    #    if _n < 0: raise ValueError
    #    cdef Integer ans = PY_NEW(Integer)
    #    mpz_set(ans.value, self.pow_mpz_t_tmp(mpz_get_si(_n.value))[0])
    #    return ans

    cdef ZZ_c* pow_ZZ_tmp(self, long n):
        """
        Provides fast access to a ZZ_c* pointing to self.prime^n.

        The location pointed to depends on the underlying representation.
        In no circumstances should you ZZ_destruct the result.
        The value pointed to may be an internal temporary variable for the class.
        In particular, you should not try to refer to the results of two
        pow_ZZ_tmp calls at the same time, because the second
        call may overwrite the memory pointed to by the first.

        See pow_ZZ_tmp_demo for an example of this phenomenon.

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 10, 10, 20, False, ntl.ZZ_pX([-5, 0, 1], 5^10), 'small', 'e',ntl.ZZ_pX([1],5^10))
        sage: PC._pow_mpz_t_tmp_test(4) #indirect doctest
        625
        """
        if n < 0:
            raise ValueError, "n must be positive"
        if n <= self.cache_limit:
            return &(self.small_powers[n])
        if n == self.prec_cap:
            return &self.top_power
        ZZ_power(self.temp_z, self.small_powers[1], n)
        return &self.temp_z

    def _pow_ZZ_tmp_test(self, n):
        """
        Tests the pow_ZZ_tmp function

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 6, 6, 12, False, ntl.ZZ_pX([-5,0,1],5^6),'small', 'e',ntl.ZZ_pX([1],5^6))
        sage: PC._pow_ZZ_tmp_test(4)
        625
        sage: PC._pow_ZZ_tmp_test(7)
        78125
        """
        cdef Integer _n = Integer(n)
        if _n < 0: raise ValueError
        cdef ntl_ZZ ans = PY_NEW(ntl_ZZ)
        ans.x = self.pow_ZZ_tmp(mpz_get_ui(_n.value))[0]
        return ans

    def _pow_ZZ_tmp_demo(self, m, n):
        """
        This function demonstrates a danger in using pow_ZZ_tmp.

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 5, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'big', 'e',ntl.ZZ_pX([1],5^10))

        When you cal pow_ZZ_tmp with an input that is not stored
        (ie n > self.cache_limit and n != self.prec_cap),
        it stores the result in self.temp_z and returns a pointer
        to that ZZ_c.  So if you try to use the results of two
        calls at once, things will break.
        sage: PC._pow_ZZ_tmp_demo(6, 8)  # 244140625 on some architectures and 152587890625 on others: random
        244140625
        sage: 5^6*5^8
        6103515625
        sage: 5^6*5^6
        244140625

        Note that this does not occur if you try a stored value,
        because the result of one of the calls points to that
        stored value.
        sage: PC._pow_ZZ_tmp_demo(6, 10)
        152587890625
        sage: 5^6*5^10
        152587890625        
        """
        m = Integer(m)
        n = Integer(n)
        if m < 0 or n < 0:
            raise ValueError, "m, n must be non-negative"
        cdef ntl_ZZ ans = PY_NEW(ntl_ZZ)
        ZZ_mul(ans.x, self.pow_ZZ_tmp(mpz_get_ui((<Integer>m).value))[0], self.pow_ZZ_tmp(mpz_get_ui((<Integer>n).value))[0])
        return ans


    cdef mpz_t* pow_mpz_t_top(self):
        """
        Returns self.prime^self.prec_cap as an mpz_t*.

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 6, 6, 12, False, ntl.ZZ_pX([-5,0,1],5^6),'small', 'e',ntl.ZZ_pX([1],5^6))
        sage: PC._pow_mpz_t_top_test() #indirect doctest
        15625
        """
        ZZ_to_mpz(&self.temp_m, &self.top_power)
        return &self.temp_m

    #def _pow_mpz_t_top_test(self):
    #    """
    #    Tests the pow_mpz_t_top function
    #
    #    EXAMPLES:
    #    sage: PC = PowComputer_ext_maker(5, 6, 6, 12, False, ntl.ZZ_pX([-5,0,1],5^6),'small', 'e',ntl.ZZ_pX([1],5^6))
    #    sage: PC._pow_mpz_t_top_test()
    #    15625
    #    """
    #    cdef Integer ans = PY_NEW(Integer)
    #    mpz_set(ans.value, self.pow_mpz_t_top()[0])
    #    return ans

    cdef ZZ_c* pow_ZZ_top(self):
        """
        Returns self.prime^self.prec_cap as a ZZ_c.

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 6, 6, 12, False, ntl.ZZ_pX([-5,0,1],5^6),'small', 'e',ntl.ZZ_pX([1],5^6))
        sage: PC._pow_ZZ_top_test() #indirect doctest
        15625
        """
        return &self.top_power

    def _pow_ZZ_top_test(self):
        """
        Tests the pow_ZZ_top function.

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 6, 6, 12, False, ntl.ZZ_pX([-5,0,1],5^6),'small', 'e',ntl.ZZ_pX([1],5^6))
        sage: PC._pow_ZZ_top_test()
        15625
        """
        cdef ntl_ZZ ans = PY_NEW(ntl_ZZ)
        ans.x = self.pow_ZZ_top()[0]
        return ans

    def _ram_prec_cap(self):
        """
        Returns the precision cap of self, considered as a power of the uniformizer.

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 6, 6, 12, False, ntl.ZZ_pX([-5,0,1],5^5),'small', 'e',ntl.ZZ_pX([1],5^5))
        """

cdef class PowComputer_ZZ_pX(PowComputer_ext):
    def __new__(self, Integer prime, long cache_limit, long prec_cap, long ram_prec_cap, bint in_field, poly, shift_seed = None):
        if not PY_TYPE_CHECK(poly, ntl_ZZ_pX):
            raise TypeError
        self.deg = ZZ_pX_deg((<ntl_ZZ_pX>poly).x)

    def polynomial(self):
        """
        Returns the polynomial (with coefficient precision prec_cap) associated to this PowComputer.

        The polynomial is output as an ntl_ZZ_pX.

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 5, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: PC.polynomial()
        [9765620 0 1]
        """
        self.restore_top_context()
        cdef ntl_ZZ_pX r = PY_NEW(ntl_ZZ_pX)
        r.c = self.get_top_context()
        r.x = (self.get_top_modulus()[0]).val()
        return r

    cdef ntl_ZZ_pContext_class get_context(self, long n):
        """
        Returns a ZZ_pContext for self.prime^(abs(n)).

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 10, 10, 20, False, ntl.ZZ_pX([-5, 0, 1], 5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: PC._get_context_test(15) #indirect doctest
        NTL modulus 30517578125
        """
        cdef ntl_ZZ pn = PY_NEW(ntl_ZZ)
        if n < 0:
            n = -n
        elif n == 0:
            raise ValueError, "n must be nonzero"
        pn.x = self.pow_ZZ_tmp(n)[0]
        cdef ntl_ZZ_pContext_class context = (<ntl_ZZ_pContext_factory>ZZ_pContext_factory).make_c(pn)
        return context

    def _get_context_test(self, n):
        """
        Returns a ZZ_pContext for self.prime^n.

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 10, 10, 20, False, ntl.ZZ_pX([-5, 0, 1], 5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: PC._get_context_test(15)
        NTL modulus 30517578125
        """
        cdef Integer _n = Integer(n)
        return self.get_context(mpz_get_si(_n.value))

    cdef ntl_ZZ_pContext_class get_context_capdiv(self, long n):
        """
        Returns a ZZ_pContext for self.prime^((n-1) // self.e + 1)

        For eisenstein extensions this gives the context used for an element of relative precision n.

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 10, 10, 20, False, ntl.ZZ_pX([-5, 0, 1], 5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: PC._get_context_capdiv_test(30) #indirect doctest
        NTL modulus 30517578125
        """
        return self.get_context(self.capdiv(n))

    def _get_context_capdiv_test(self, n):
        """
        Returns a ZZ_pContext for self.prime^((n-1) // self.e + 1)

        For eisenstein extensions this gives the context used for an element of relative precision n.        

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 10, 10, 20, False, ntl.ZZ_pX([-5, 0, 1], 5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: PC._get_context_capdiv_test(29)
        NTL modulus 30517578125
        """
        cdef Integer _n = Integer(n)
        return self.get_context_capdiv(mpz_get_si(_n.value))

    def speed_test(self, n, runs):
        """
        Runs a speed test.

        INPUT:
        n -- input to a function to be tested (the function needs to be set in the source code).
        runs -- The number of runs of that function
        OUTPUT:
        The time in seconds that it takes to call the function on n, runs times.

        sage: PC = PowComputer_ext_maker(5, 10, 10, 20, False, ntl.ZZ_pX([-5, 0, 1], 5^10), 'small', 'e',ntl.ZZ_pX([1],5^10))
        sage: PC.speed_test(10, 10^6) # random
        0.0090679999999991878 
        """
        cdef Py_ssize_t i, end, _n
        end = mpz_get_ui((<Integer>Integer(runs)).value)
        _n = mpz_get_ui((<Integer>Integer(n)).value)
        t = cputime()
        for i from 0 <= i < end:
            # Put the function you want speed tested here.
            self.get_modulus(_n)
        return cputime(t)
    
    cdef ntl_ZZ_pContext_class get_top_context(self):
        """
        Returns a ZZ_pContext for self.prime^self.prec_cap

        sage: PC = PowComputer_ext_maker(5, 5, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: PC._get_top_context_test() #indirect doctest
        NTL modulus 9765625
        """
        return self.get_context(self.prec_cap)

    def _get_top_context_test(self):
        """
        Returns a ZZ_pContext for self.prime^self.prec_cap
        
        sage: PC = PowComputer_ext_maker(5, 5, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: PC._get_top_context_test()
        NTL modulus 9765625
        """
        return self.get_top_context()
        
    cdef restore_context(self, long n):
        """
        Restores the contest corresponding to self.prime^n

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 5, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: PC._restore_context_test(4) #indirect doctest
        """
        self.get_context(n).restore_c()

    def _restore_context_test(self, n):
        """
        Restores the contest corresponding to self.prime^n

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 5, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: PC._restore_context_test(4)
        """
        cdef Integer _n = Integer(n)
        self.restore_context(mpz_get_si(_n.value))

    cdef restore_context_capdiv(self, long n):
        """
        Restores the context for self.prime^((n-1) // self.e + 1)

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 5, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: PC._restore_context_capdiv_test(4) #indirect doctest
        """
        self.restore_context(self.capdiv(n))

    def _restore_context_capdiv_test(self, n):
        """
        Restores the context for self.prime^((n-1) // self.e + 1)

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 5, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: PC._restore_context_capdiv_test(8) #indirect doctest
        """
        cdef Integer _n = Integer(n)
        self.restore_context_capdiv(mpz_get_si(_n.value))

    cdef void restore_top_context(self):
        """
        Restores the context corresponding to self.prime^self.prec_cap

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 5, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: PC._restore_top_context_test()        
        """
        (<ntl_ZZ_pContext_class>self.get_top_context()).restore_c()

    def _restore_top_context_test(self):
        """
        Restores the context corresponding to self.prime^self.prec_cap

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 5, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: PC._restore_top_context_test()
        """
        self.restore_top_context()
    
    cdef ZZ_pX_Modulus_c* get_modulus(self, long n):
        """
        Returns the modulus corresponding to self.polynomial() (mod self.prime^n)

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 10, 1000, 2000, False, ntl.ZZ_pX([-5,0,1],5^1000), 'big', 'e',ntl.ZZ_pX([1],5^1000))
        sage: a = ntl.ZZ_pX([4,2],5^2)
        sage: b = ntl.ZZ_pX([6,3],5^2)
        sage: A._get_modulus_test(a, b, 2) # indirect doctest
        [4 24]
        """
        raise NotImplementedError

    def _get_modulus_test(self, ntl_ZZ_pX a, ntl_ZZ_pX b, Integer n):
        """
        Multiplies a and b modulo the modulus corresponding to self.polynomial() (mod self.prime^n).

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 10, 1000, 2000, False, ntl.ZZ_pX([-5,0,1],5^1000), 'big', 'e',ntl.ZZ_pX([1],5^1000))
        sage: a = ntl.ZZ_pX([4,2],5^2)
        sage: b = ntl.ZZ_pX([6,3],5^2)
        sage: A._get_modulus_test(a, b, 2)
        [4 24]
        sage: a * b
        [24 24 6]
        sage: mod(6 * 5 + 24, 25)
        4
        """
        if self.pow_Integer(mpz_get_si(n.value)) != Integer(a.c.p):
            #print self.pow_Integer(mpz_get_si(n.value))
            #print a.c.p
            raise ValueError, "a context mismatch"
        if self.pow_Integer(mpz_get_si(n.value)) != Integer(b.c.p):
            #print self.pow_Integer(mpz_get_si(n.value))
            #print b.c.p
            raise ValueError, "b context mismatch"
        cdef ntl_ZZ_pX r = (<ntl_ZZ_pX>a)._new()
        cdef ntl_ZZ_pX aa = (<ntl_ZZ_pX>a)._new()
        cdef ntl_ZZ_pX bb = (<ntl_ZZ_pX>b)._new()
        ZZ_pX_rem(aa.x, a.x, self.get_modulus(mpz_get_si(n.value))[0].val())
        ZZ_pX_rem(bb.x, b.x, self.get_modulus(mpz_get_si(n.value))[0].val())
        ZZ_pX_MulMod_pre(r.x, aa.x, bb.x, self.get_modulus(mpz_get_si(n.value))[0])
        return r

    cdef ZZ_pX_Modulus_c* get_modulus_capdiv(self, long n):
        """
        Returns the modulus corresponding to self.polynomial() (mod self.prime^((n-1) // self.e + 1)
        """
        return self.get_modulus(self.capdiv(n))

    cdef ZZ_pX_Modulus_c* get_top_modulus(self):
        """
        Returns the modulus corresponding to self.polynomial() (mod self.prime^self.prec_cap)

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 3, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: a = ntl.ZZ_pX([129223,1231],5^10)
        sage: b = ntl.ZZ_pX([289741,323],5^10)
        sage: A._get_top_modulus_test(a, b) #indirect doctest
        [1783058 7785200]         
        """
        raise NotImplementedError

    def _get_top_modulus_test(self, ntl_ZZ_pX a, ntl_ZZ_pX b):
        """
        Multiplies a and b modulo the modulus corresponding to self.polynomial() (mod self.prime^self.prec_cap)

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 3, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: a = ntl.ZZ_pX([129223,1231],5^10)
        sage: b = ntl.ZZ_pX([289741,323],5^10)
        sage: A._get_top_modulus_test(a, b) 
        [1783058 7785200]
        sage: a*b
        [9560618 7785200 397613]
        sage: mod(397613 * 5 + 9560618, 5^10)
        1783058
        """
        cdef ntl_ZZ_pX ans = a._new()
        ZZ_pX_MulMod_pre(ans.x, a.x, b.x, self.get_top_modulus()[0])
        return ans

    cdef long capdiv(self, long n):
        """
        If n >= 0 returns ceil(n / self.e)

        If n < 0 returns ceil(-n / self.e)

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 3, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: PC._capdiv_test(15)
        8
        sage: PC._capdiv_test(-7)
        4
        """
        if self.e == 1:
            return n
        if n > 0:
            return (n-1) / self.e + 1
        elif n < 0:
            return (-1-n) / self.e + 1
        else:
            return 0

    def _capdiv_test(self, n):
        """
        If n >= 0 returns ceil(n / self.e)

        If n < 0 returns ceil(-n / self.e)

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 3, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: PC._capdiv_test(15)
        8
        sage: PC._capdiv_test(-7)
        4
        """
        cdef Integer _n = Integer(n)
        cdef Integer ans = PY_NEW(Integer)
        mpz_set_si(ans.value, self.capdiv(mpz_get_si(_n.value)))
        return ans
        
    cdef int eis_shift(self, ZZ_pX_c* x, ZZ_pX_c* a, long n, long finalprec) except -1:
        raise NotImplementedError

    cdef int eis_shift_capdiv(self, ZZ_pX_c* x, ZZ_pX_c* a, long n, long finalprec) except -1:
        return self.eis_shift(x, a, n, self.capdiv(finalprec))

    cdef int teichmuller_set_c (self, ZZ_pX_c* x, ZZ_pX_c* a, long absprec) except -1:
        r"""
        Sets x to the Teichmuller lift congruent to a modulo the uniformizer, ie such that $x = a \mod \pi$
        and $x^q = x \mod \pi^{\mbox{absprec}}$.
        If $a = 0 \mod \pi$ does nothing and returns 1.  Otherwise returns 0.
        x should be created with context p^absprec.
        Does not affect self.
        
        INPUT:
        x -- The ZZ_pX_c to be set
        a -- A ZZ_pX_c currently holding an approximation to the
             Teichmuller representative (this approximation can
             be any integer).  It will be set to the actual
             Teichmuller lift
        absprec -- the desired precision of the Teichmuller lift
        OUTPUT:
        1 -- x should be set to zero (or usually, ZZ_pX_destruct'd)
        0 -- normal

        EXAMPLES:
        sage: R = Zp(5,5)
        sage: S.<x> = R[]
        sage: f = x^5 + 75*x^3 - 15*x^2 +125*x - 5
        sage: W.<w> = R.ext(f)
        sage: y = W.teichmuller(3); y
        3 + 3*w^5 + w^7 + 2*w^9 + 2*w^10 + 4*w^11 + w^12 + 2*w^13 + 3*w^15 + 2*w^16 + 3*w^17 + w^18 + 3*w^19 + 3*w^20 + 2*w^21 + 2*w^22 + 3*w^23 + 4*w^24 + O(w^25)
        sage: y^5 == y
        True
        sage: g = x^3 + 3*x + 3
        sage: A.<a> = R.ext(g)
        sage: b = A.teichmuller(1 + 2*a - a^2); b
        (4*a^2 + 2*a + 1) + 2*a*5 + (3*a^2 + 1)*5^2 + (a + 4)*5^3 + (a^2 + a + 1)*5^4 + O(5^5)
        sage: b^125 == b
        True
        """
        cdef mpz_t u, xnew, value
        cdef ZZ_c tmp, q, u_q
        cdef ZZ_pX_c xnew_q
        cdef ntl_ZZ_pContext_class c
        cdef long mini, minval
        if absprec == 0:
            return 1
        if absprec < 0:
            absprec = -absprec
        if self.e != 1:
            mpz_init(value)
            tmp = ZZ_p_rep(ZZ_pX_ConstTerm(a[0]))
            ZZ_to_mpz(&value, &tmp)
            if mpz_divisible_p(value, self.prime.value) != 0:
                mpz_clear(value)
                return 1
            self.pow_mpz_t_tmp(self.capdiv(absprec)) # sets self.temp_m
            if mpz_sgn(value) < 0 or mpz_cmp(value, self.temp_m) >= 0:
                mpz_mod(value, value, self.temp_m)
            mpz_init(u)
            mpz_init(xnew)
            # u = 1 / Mod(1 - p, self.temp_m)
            mpz_sub(u, self.temp_m, self.prime.value)
            mpz_add_ui(u, u, 1)
            mpz_invert(u, u, self.temp_m)
            # Consider x as Mod(self.value, self.temp_m)
            # xnew = x + u*(x^p - x)
            mpz_powm(xnew, value, self.prime.value, self.temp_m)
            mpz_sub(xnew, xnew, value)
            mpz_mul(xnew, xnew, u)
            mpz_add(xnew, xnew, value)
            mpz_mod(xnew, xnew, self.temp_m)
            # while x != xnew:
            #     x = xnew
            #     xnew = x + u*(x^p - x)
            while mpz_cmp(value, xnew) != 0:
                mpz_set(value, xnew)
                mpz_powm(xnew, value, self.prime.value, self.temp_m)
                mpz_sub(xnew, xnew, value)
                mpz_mul(xnew, xnew, u)
                mpz_add(xnew, xnew, value)
                mpz_mod(xnew, xnew, self.temp_m)
            mpz_clear(u)
            mpz_clear(xnew)
            mpz_to_ZZ(&tmp, &value)
            self.restore_context_capdiv(absprec)
            if ZZ_pX_IsZero(x[0]): # shortcut for the case x = 0
                ZZ_pX_SetCoeff(x[0], 0, ZZ_to_ZZ_p(tmp))
            else:
                ZZ_pX_SetX(x[0])
                ZZ_pX_SetCoeff(x[0], 0, ZZ_to_ZZ_p(tmp))
                ZZ_pX_SetCoeff_long(x[0], 1, 0)
            mpz_clear(value)
        else:
            c = self.get_context(absprec)
            c.restore_c()
            q = self.pow_ZZ_tmp(self.f)[0]
            ZZ_pX_min_val_coeff(minval, mini, a[0], self.pow_ZZ_tmp(1)[0])
            if mini == -1 or minval > 0:
                return 1
            ZZ_pX_conv_modulus(x[0], a[0], c.x)
            # u = 1 / Mod(1 - q, p^absprec)
            ZZ_conv_from_long(u_q, 1)
            ZZ_sub(u_q, u_q, q)
            ZZ_rem(u_q, u_q, (<ntl_ZZ>c.p).x)
            ZZ_InvMod(u_q, u_q, (<ntl_ZZ>c.p).x)
            # xnew = x + u*(x^q - x)
            ZZ_pX_PowerMod_pre(xnew_q, x[0], q, self.get_modulus(absprec)[0])
            ZZ_pX_sub(xnew_q, xnew_q, x[0])
            ZZ_pX_mul_ZZ_p(xnew_q, xnew_q, ZZ_to_ZZ_p(u_q))
            ZZ_pX_add(xnew_q, xnew_q, x[0])
            # while x != xnew:
            #     x = xnew
            #     xnew = x + u*(x^p - x)
            while not ZZ_pX_equal(x[0], xnew_q):
                x[0] = xnew_q
                ZZ_pX_PowerMod_pre(xnew_q, x[0], q, self.get_modulus(absprec)[0])
                ZZ_pX_sub(xnew_q, xnew_q, x[0])
                ZZ_pX_mul_ZZ_p(xnew_q, xnew_q, ZZ_to_ZZ_p(u_q))
                ZZ_pX_add(xnew_q, xnew_q, x[0])
        return 0            

cdef class PowComputer_ZZ_pX_FM(PowComputer_ZZ_pX):
    """
    This class only caches a context and modulus for p^prec_cap.
    Designed for use with fixed modulus p-adic rings, in Eisenstein and unramified extensions of $\mathbb{Z}_p$.
    """

    def __new__(self, Integer prime, long cache_limit, long prec_cap, long ram_prec_cap, bint in_field, poly, shift_seed = None):
        """
        Caches a context and modulus for prime^prec_cap

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 3, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10)) #indirect doctest
        sage: A
        PowComputer_ext for 5, with polynomial [9765620 0 1]
        """

        # The __new__ method for PowComputer_ext has already run, so we have access to small_powers, top_power.

        # We use ntl_ZZ_pContexts so that contexts are cached centrally.

        self._prec_type = 'FM'
        self._ext_type = 'u'
        self.c = self.get_context(prec_cap)
        self.c.restore_c()
        # For now, we don't do anything complicated with poly
        if PY_TYPE_CHECK(poly, ntl_ZZ_pX) and (<ntl_ZZ_pX>poly).c is self.c:
            ZZ_pX_Modulus_construct(&self.mod)
            ZZ_pX_Modulus_build(self.mod, (<ntl_ZZ_pX>poly).x)
            if prec_cap == ram_prec_cap:
                self.e = 1
                self.f = ZZ_pX_deg((<ntl_ZZ_pX>poly).x)
            else:
                self.e = ZZ_pX_deg((<ntl_ZZ_pX>poly).x)
                self.f = 1
            self.ram_prec_cap = ram_prec_cap
        else:
            raise NotImplementedError, "NOT IMPLEMENTED IN PowComputer_ZZ_pX_FM"


    def __dealloc__(self):
        """
        Cleans up the memory for self.mod

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 3, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: del A # indirect doctest
        """
        if self._initialized:
            self.cleanup_ZZ_pX_FM()

    cdef void cleanup_ZZ_pX_FM(self):
        """
        Cleans up the memory for self.mod

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 3, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10)) #indirect doctest
        sage: del A # indirect doctest
        """
        ZZ_pX_Modulus_destruct(&self.mod)

    cdef ntl_ZZ_pContext_class get_top_context(self):
        """
        Returns a ZZ_pContext for self.prime^self.prec_cap
        
        sage: PC = PowComputer_ext_maker(5, 5, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: PC._get_top_context_test() # indirect doctest
        NTL modulus 9765625
        """
        return self.c

    cdef void restore_top_context(self):
        """
        Restores the context corresponding to self.prime^self.prec_cap

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 5, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: PC._restore_top_context_test() #indirect doctest        
        """
        self.c.restore_c()

    cdef ZZ_pX_Modulus_c* get_top_modulus(self):
        """
        Returns the modulus corresponding to self.polynomial() (mod self.prime^self.prec_cap)

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 3, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: a = ntl.ZZ_pX([129223,1231],5^10)
        sage: b = ntl.ZZ_pX([289741,323],5^10)
        sage: A._get_top_modulus_test(a, b) #indirect doctest
        [1783058 7785200]         
        """
        return &self.mod

    cdef ZZ_pX_Modulus_c* get_modulus(self, long n):
        """
        Duplicates functionality of get_top_modulus if n == self.prec_cap.

        If not, raises an error.

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 3, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'FM', 'e',ntl.ZZ_pX([1],5^10))
        sage: a = ntl.ZZ_pX([129223,1231],5^10)
        sage: b = ntl.ZZ_pX([289741,323],5^10)
        sage: A._get_modulus_test(a, b, 10) #indirect doctest
        [1783058 7785200]
        """
        if n == self.prec_cap:
            return &self.mod
        else:
            raise ValueError, "fixed modulus PowComputers only store top modulus"

cdef class PowComputer_ZZ_pX_FM_Eis(PowComputer_ZZ_pX_FM):
    """
    This class computes and stores low_shifter and high_shifter, which aid in right shifting elements.
    """

    def __new__(self, Integer prime, long cache_limit, long prec_cap, long ram_prec_cap, bint in_field, poly, shift_seed = None):
        # The __new__ method for PowComputer_ZZ_pX_FM has already run, so we have access to self.mod
        self._ext_type = 'e'
        if not PY_TYPE_CHECK(shift_seed, ntl_ZZ_pX):
            raise TypeError, "shift_seed must be an ntl_ZZ_pX"
        ZZ_pX_Eis_init(self, <ntl_ZZ_pX>shift_seed)

    def _low_shifter(self, i):
        cdef long _i = i
        cdef ntl_ZZ_pX ans
        if _i >= 0 and _i < self.low_length:
            ans = ntl_ZZ_pX([], self.get_top_context())
            ans.x = self.low_shifter[i].val()
            return ans
        else:
            raise IndexError

    def _high_shifter(self, i):
        cdef long _i = i
        cdef ntl_ZZ_pX ans
        if _i >= 0 and _i < self.high_length:
            ans = ntl_ZZ_pX([], self.get_top_context())
            ans.x = self.high_shifter[i].val()
            return ans
        else:
            raise IndexError
        
    def __dealloc__(self):
        if self._initialized:
            self.cleanup_ZZ_pX_FM_Eis()

    cdef void cleanup_ZZ_pX_FM_Eis(self):
        cdef int i # yes, an int is good enough
        for i from 0 <= i < self.low_length:
            ZZ_pX_Multiplier_destruct(&(self.low_shifter[i]))
        sage_free(self.low_shifter)
        for i from 0 <= i < self.high_length:
            ZZ_pX_Multiplier_destruct(&(self.high_shifter[i]))
        sage_free(self.high_shifter)

    cdef int eis_shift(self, ZZ_pX_c* x, ZZ_pX_c* a, long n, long finalprec) except -1:
        return ZZ_pX_eis_shift(self, x, a, n, finalprec)

#         ##print "starting..."
#         cdef ZZ_pX_c low_part
#         cdef ZZ_pX_c shifted_high_part
#         cdef ZZ_pX_c high_shifter

#         ##cdef ntl_ZZ_pX printer
#         if n < 0:
#             self.restore_top_context()
#             ##printer = ntl_ZZ_pX([],self.get_top_context())
#             ZZ_pX_PowerXMod_long_pre(high_shifter, -n, self.get_top_modulus()[0])
#             ##printer.x = high_shifter
#             ##print printer
#             ZZ_pX_MulMod_pre(x[0],high_shifter,a[0],self.get_top_modulus()[0])
#             ##printer.x = x[0]
#             ##print printer
#             return 0
#         elif n == 0:
#             if x != a:
#                 x[0] = a[0]
#             return 0
#         cdef long pshift = n / self.e
#         cdef long eis_part = n % self.e
#         cdef long two_shift = 1
#         cdef int i

#         ##printer = ntl_ZZ_pX([],self.get_top_context())
#         ##print "eis_part: %s" %(eis_part)
#         ##print "pshift: %s"%(pshift)
#         if x != a:
#             ##print "copying"
#             x[0] = a[0]
#         ##printer.x = a[0]
#         ##print "beginning: a = %s"%(printer)
#         if pshift:
#             i = 0
#             # This line restores the top context
#             ZZ_pX_right_pshift(x[0], x[0], self.pow_ZZ_tmp(pshift)[0], self.get_top_context().x)
#             ##printer.x = x[0]
#             ##print printer
#             if pshift >= self.prec_cap:
#                 # high_shifter = p^(2^(high_length - 1))/x^(e*2^(high_length - 1))
#                 # if val = r + s * 2^(high_length - 1)
#                 # then high_shifter = p^(s*2^(high_length - 1))/x^(e*s*2^(high_length - 1))
#                 ZZ_pX_PowerMod_long_pre(high_shifter, self.high_shifter[self.high_length-1].val(), (pshift / (1L << (self.high_length - 1))), self.get_top_modulus()[0])
#                 ##printer.x = high_shifter
#                 ##print printer
#                 ZZ_pX_MulMod_pre(x[0], x[0], high_shifter, self.get_top_modulus()[0])
#                 ##printer.x = high_shifter
#                 ##print printer
#                 # Now we only need to multiply self.unit by p^r/x^(e*r) where r < 2^(high_length - 1), which is tractible.
#                 pshift = pshift % (1L << (self.high_length - 1))
#             while pshift > 0:
#                 if pshift & 1:
#                     ##print "pshift = %s"%pshift
#                     ##printer.x = x[0]
#                     ##print printer
#                     ZZ_pX_MulMod_premul(x[0], x[0], self.high_shifter[i], self.get_top_modulus()[0])
#                 i += 1
#                 pshift = pshift >> 1
#         else:
#             self.restore_top_context()
#         i = 0
#         two_shift = 1
#         while eis_part > 0:
#             ##print "eis_part = %s"%(eis_part)
#             if eis_part & 1:
#                 ##print "i = %s"%(i)
#                 ##print "two_shift = %s"%(two_shift)
#                 ZZ_pX_RightShift(shifted_high_part, x[0], two_shift)
#                 ##printer.x = shifted_high_part
#                 ##print "shifted_high_part = %s"%(printer)
#                 ZZ_pX_LeftShift(low_part, shifted_high_part, two_shift)
#                 ZZ_pX_sub(low_part, x[0], low_part)
#                 ##printer.x = low_part
#                 ##print "low_part = %s"%(printer)
#                 ZZ_pX_right_pshift(low_part, low_part, self.pow_ZZ_tmp(1)[0], self.get_top_context().x)
#                 ##printer.x = low_part
#                 ##print "low_part = %s"%(printer)
#                 ZZ_pX_MulMod_premul(low_part, low_part, self.low_shifter[i], self.get_top_modulus()[0])
#                 ##printer.x = low_part
#                 ##print "low_part = %s"%(printer)
#                 ZZ_pX_add(x[0], low_part, shifted_high_part)
#                 ##printer.x = x[0]
#                 ##print "x = %s"%(printer)
#             i += 1
#             two_shift = two_shift << 1
#             eis_part = eis_part >> 1

cdef class PowComputer_ZZ_pX_small(PowComputer_ZZ_pX):
    """
    This class caches contexts and moduli densely between 1 and cache_limit.  It requires cache_limit == prec_cap.

    It is intended for use with capped relative and capped absolute rings and fields, in Eisenstein and unramified
    extensions of the base p-adic fields.
    """

    def __new__(self, Integer prime, long cache_limit, long prec_cap, long ram_prec_cap, bint in_field, poly, shift_seed = None):
        """
        Caches contexts and moduli densely between 1 and cache_limit.

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 10, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'small', 'e',ntl.ZZ_pX([1],5^10)) # indirect doctest
        sage: A
        PowComputer_ext for 5, with polynomial [9765620 0 1]
        """
        # The __new__ method for PowComputer_ext has already run, so we have access to small_powers, top_power.

        # We use ntl_ZZ_pContexts so that contexts are cached centrally.

        self._prec_type = 'small'
        self._ext_type = 'u'
        if not PY_TYPE_CHECK(poly, ntl_ZZ_pX):
            self.cleanup_ext()
            raise TypeError

        if cache_limit != prec_cap:
            self.cleanup_ext()
            raise ValueError, "prec_cap and cache_limit must be equal in the small case"

        self.c = []
        # We cache from 0 to cache_limit inclusive, and provide one extra slot to return moduli above the cache_limit
        _sig_on
        self.mod = <ZZ_pX_Modulus_c *>sage_malloc(sizeof(ZZ_pX_Modulus_c) * (cache_limit + 2))
        _sig_off
        if self.mod == NULL:
            self.cleanup_ext()
            raise MemoryError, "out of memory allocating moduli"

        cdef ntl_ZZ_pX printer
        cdef Py_ssize_t i
        cdef ZZ_pX_c tmp, pol
        if PY_TYPE_CHECK(poly, ntl_ZZ_pX):
            pol = (<ntl_ZZ_pX>poly).x
            self.c.append(None)
            for i from 1 <= i <= cache_limit:
                self.c.append(PowComputer_ZZ_pX.get_context(self,i))
                (<ntl_ZZ_pContext_class>self.c[i]).restore_c()
                ZZ_pX_Modulus_construct(&(self.mod[i]))
                ZZ_pX_conv_modulus(tmp, pol, (<ntl_ZZ_pContext_class>self.c[i]).x)
                ZZ_pX_Modulus_build(self.mod[i], tmp)
            ZZ_pX_Modulus_construct(&(self.mod[cache_limit+1]))
            if prec_cap == ram_prec_cap:
                self.e = 1
                self.f = ZZ_pX_deg((<ntl_ZZ_pX>poly).x)
            else:
                self.e = ZZ_pX_deg((<ntl_ZZ_pX>poly).x)
                self.f = 1
            self.ram_prec_cap = ram_prec_cap
        else:
            raise NotImplementedError, "NOT IMPLEMENTED IN PowComputer_ZZ_pX_FM"            
            
    def __dealloc__(self):
        """
        Deallocates cache of contexts, moduli.

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 10, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'small','e',ntl.ZZ_pX([1],5^10))
        sage: del A # indirect doctest
        """
        if self._initialized:
            self.cleanup_ZZ_pX_small()

    cdef void cleanup_ZZ_pX_small(self):
        """
        Deallocates cache of contexts, moduli.

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 10, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'small','e',ntl.ZZ_pX([1],5^10))
        sage: del A # indirect doctest
        """
        cdef Py_ssize_t i
        for i from 1 <= i <= self.cache_limit + 1:
            ZZ_pX_Modulus_destruct(&(self.mod[i]))
        sage_free(self.mod)

    cdef ntl_ZZ_pContext_class get_context(self, long n):
        """
        Returns the context for p^n.

        Note that this function will raise an Index error if n > self.cache_limit.
        Also, it will return None on input 0

        INPUT:
        n -- A long between 1 and self.cache_limit, inclusive
        OUTPUT:
        A context for p^n

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 10, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'small','e',ntl.ZZ_pX([1],5^10))
        sage: A._get_context_test(4) #indirect doctest
        NTL modulus 625
        """
        if n < 0:
            n = -n
        try:
            return self.c[n]
        except IndexError:
            return PowComputer_ZZ_pX.get_context(self, n)

    cdef restore_context(self, long n):
        """
        Restores the context for p^n.

        INPUT:
        n -- A long between 1 and self.cache_limit, inclusive

        EXAMPLES: 
        sage: A = PowComputer_ext_maker(5, 10, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'small','e',ntl.ZZ_pX([1],5^10))
        sage: A._restore_context_test(4) #indirect doctest
        """
        if n < 0:
            n = -n
        try:
            _sig_on
            (<ntl_ZZ_pContext_class>self.c[n]).restore_c()
            _sig_off
        except IndexError:
            _sig_on
            (<ntl_ZZ_pContext_class>PowComputer_ZZ_pX.get_context(self, n)).restore_c()
            _sig_off

    cdef ntl_ZZ_pContext_class get_top_context(self):
        """
        Returns a ZZ_pContext for self.prime^self.prec_cap
        
        sage: PC = PowComputer_ext_maker(5, 10, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'small','e',ntl.ZZ_pX([1],5^10))
        sage: PC._get_top_context_test() # indirect doctest
        NTL modulus 9765625
        """        
        return self.c[self.prec_cap]

    cdef void restore_top_context(self):
        """
        Restores the context corresponding to self.prime^self.prec_cap

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 10, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'small','e',ntl.ZZ_pX([1],5^10))
        sage: PC._restore_top_context_test() #indirect doctest        
        """
        (<ntl_ZZ_pContext_class>self.c[self.prec_cap]).restore_c()

    cdef ZZ_pX_Modulus_c* get_modulus(self, long n):
        """
        Returns the modulus corresponding to self.polynomial() (mod self.prime^n).

        INPUT:
        n -- A long between 1 and self.cache_limit, inclusive
             if n is larger, this function will return self.mod[prec_cap] lifted to that precision.

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 10, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'small','e',ntl.ZZ_pX([1],5^10))
        sage: a = ntl.ZZ_pX([4,2],5^2)
        sage: b = ntl.ZZ_pX([6,3],5^2)
        sage: A._get_modulus_test(a, b, 2)
        [4 24]
        """
        cdef ZZ_pX_c tmp
        if n < 0:
            n = -n
        if n <= self.prec_cap:
            return &(self.mod[n])
        else:
            ZZ_pX_conv_modulus(tmp, self.mod[self.prec_cap].val(), (<ntl_ZZ_pContext_class>self.get_context(n)).x)
            ZZ_pX_Modulus_build(self.mod[self.prec_cap+1], tmp)
            return &(self.mod[self.prec_cap+1])

    cdef ZZ_pX_Modulus_c* get_top_modulus(self):
        """
        Returns the modulus corresponding to self.polynomial() (mod self.prime^self.prec_cap)

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 10, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'small','e',ntl.ZZ_pX([1],5^10))
        sage: a = ntl.ZZ_pX([129223,1231],5^10)
        sage: b = ntl.ZZ_pX([289741,323],5^10)
        sage: A._get_top_modulus_test(a, b) #indirect doctest
        [1783058 7785200]         
        """
        return &(self.mod[self.prec_cap])

cdef class PowComputer_ZZ_pX_small_Eis(PowComputer_ZZ_pX_small):
    """
    This class computes and stores low_shifter and high_shifter, which aid in right shifting elements.
    These are only stored at maximal precision: in order to get lower precision versions just reduce mod p^n.
    """
    def __new__(self, Integer prime, long cache_limit, long prec_cap, long ram_prec_cap, bint in_field, poly, shift_seed = None):
        self._ext_type = 'e'
        if not PY_TYPE_CHECK(shift_seed, ntl_ZZ_pX):
            raise TypeError, "shift_seed must be an ntl_ZZ_pX"
        ZZ_pX_Eis_init(self, <ntl_ZZ_pX>shift_seed)
    
    def _low_shifter(self, i):
        cdef long _i = i
        cdef ntl_ZZ_pX ans
        if _i >= 0 and _i < self.low_length:
            ans = ntl_ZZ_pX([], self.get_top_context())
            ans.x = self.low_shifter[i]
            return ans
        else:
            raise IndexError

    def _high_shifter(self, i):
        cdef long _i = i
        cdef ntl_ZZ_pX ans
        if _i >= 0 and _i < self.high_length:
            ans = ntl_ZZ_pX([], self.get_top_context())
            ans.x = self.high_shifter[i]
            return ans
        else:
            raise IndexError
                    

    def __dealloc__(self):
        if self._initialized:
            self.cleanup_ZZ_pX_small_Eis()

    cdef void cleanup_ZZ_pX_small_Eis(self):
        #pass
        # I may or may not need to deallocate these:
        #
        cdef int i # yes, an int is good enough
        for i from 0 <= i < self.low_length:
            ZZ_pX_destruct(&(self.low_shifter[i]))
        sage_free(self.low_shifter)
        for i from 0 <= i < self.high_length:
            ZZ_pX_destruct(&(self.high_shifter[i]))
        sage_free(self.high_shifter)

    cdef int eis_shift(self, ZZ_pX_c* x, ZZ_pX_c* a, long n, long finalprec) except -1:
        return ZZ_pX_eis_shift(self, x, a, n, finalprec)

cdef class PowComputer_ZZ_pX_big(PowComputer_ZZ_pX):
    """
    This class caches all contexts and moduli between 1 and cache_limit, and also caches for prec_cap.  In addition, it stores
    a dictionary of contexts and moduli of 
    """

    def __new__(self, Integer prime, long cache_limit, long prec_cap, long ram_prec_cap, bint in_field, poly, shift_seed = None):
        """
        Caches contexts and moduli densely between 1 and cache_limit.  Caches a context and modulus for prec_cap.
        Also creates the dictionaries.

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 6, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'big','e',ntl.ZZ_pX([1],5^10)) # indirect doctest
        sage: A
        PowComputer_ext for 5, with polynomial [9765620 0 1]
        """
        # The __new__ method for PowComputer_ext has already run, so we have access to small_powers, top_power.

        # We use ntl_ZZ_pContexts so that contexts are cached centrally.

        self._prec_type = 'big'
        self._ext_type = 'u'
        if not PY_TYPE_CHECK(poly, ntl_ZZ_pX):
            self.cleanup_ext()
            raise TypeError

        self.context_list = []
        #if self.c == NULL:
        #    self.cleanup_ext()
        #    raise MemoryError, "out of memory allocating contexts"
        _sig_on
        self.modulus_list = <ZZ_pX_Modulus_c *>sage_malloc(sizeof(ZZ_pX_Modulus_c) * (cache_limit + 1))
        _sig_off
        if self.modulus_list == NULL:
            self.cleanup_ext()
            raise MemoryError, "out of memory allocating moduli"

        cdef Py_ssize_t i
        cdef ZZ_pX_c tmp, pol
        if PY_TYPE_CHECK(poly, ntl_ZZ_pX):
            pol = (<ntl_ZZ_pX>poly).x
            self.context_list.append(None)
            for i from 1 <= i <= cache_limit:
                self.context_list.append(PowComputer_ZZ_pX.get_context(self,i))
                ZZ_pX_Modulus_construct(&(self.modulus_list[i]))
                ZZ_pX_conv_modulus(tmp, pol, (<ntl_ZZ_pContext_class>self.context_list[i]).x)
                ZZ_pX_Modulus_build(self.modulus_list[i], tmp)
            self.top_context = PowComputer_ZZ_pX.get_context(self, prec_cap)
            ZZ_pX_Modulus_construct(&(self.top_mod))
            ZZ_pX_conv_modulus(tmp, pol, self.top_context.x)
            ZZ_pX_Modulus_build(self.top_mod, tmp)
            self.context_dict = {}
            self.modulus_dict = {}
            if prec_cap == ram_prec_cap:
                self.e = 1
                self.f = ZZ_pX_deg((<ntl_ZZ_pX>poly).x)
            else:
                self.e = ZZ_pX_deg((<ntl_ZZ_pX>poly).x)
                self.f = 1
            self.ram_prec_cap = ram_prec_cap
        else:
            raise NotImplementedError, "NOT IMPLEMENTED IN PowComputer_ZZ_pX_FM"

    def __dealloc__(self):
        """
        Deallocates the stored moduli and contexts.

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 6, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'big','e',ntl.ZZ_pX([1],5^10)) 
        sage: del A # indirect doctest
        """
        if self._initialized:
            self.cleanup_ZZ_pX_big()

    cdef void cleanup_ZZ_pX_big(self):
        """
        Deallocates the stored moduli and contexts.

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 6, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'big','e',ntl.ZZ_pX([1],5^10)) 
        sage: del A # indirect doctest
        """
        #pass
        ## These cause a segfault.  I don't know why.
        cdef Py_ssize_t i
        for i from 1 <= i <= self.cache_limit:
            ZZ_pX_Modulus_destruct(&(self.modulus_list[i]))
        sage_free(self.modulus_list)
        ZZ_pX_Modulus_destruct(&self.top_mod)

    def reset_dictionaries(self):
        """
        Resets the dictionaries.  Note that if there are elements lying around that need access to these dictionaries, calling this function and then doing arithmetic with those elements could cause trouble (if the context object gets garbage collected for example.  The bugs introduced could be very subtle, because NTL will generate a new context object and use it, but there's the potential for the object to be incompatible with the different context object).

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 6, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'big','e',ntl.ZZ_pX([1],5^10))
        sage: P = A._get_context_test(8)
        sage: A._context_dict()
        {8: NTL modulus 390625}
        sage: A.reset_dictionaries()
        sage: A._context_dict()
        {}
        """
        self.context_dict = {}
        self.modulus_dict = {}

    def _context_dict(self):
        """
        Returns the context dictionary.

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 6, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'big','e',ntl.ZZ_pX([1],5^10))
        sage: P = A._get_context_test(8)
        sage: A._context_dict()
        {8: NTL modulus 390625}        
        """
        return self.context_dict

    def _modulus_dict(self):
        """
        Returns the context dictionary.

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 6, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'big','e',ntl.ZZ_pX([1],5^10))
        sage: P = A._get_context_test(8)
        sage: A._modulus_dict()
        {}
        sage: a = ntl.ZZ_pX([4,2],5^8)
        sage: b = ntl.ZZ_pX([6,3],5^8)
        sage: A._get_modulus_test(a, b, 8)
        [54 24]
        sage: A._modulus_dict()
        {8: NTL ZZ_pXModulus [390620 0 1] (mod 390625)}
        """
        return self.modulus_dict

    cdef ntl_ZZ_pContext_class get_context(self, long n):
        """
        Returns the context for p^n.

        Note that this function will raise an Index error if n > self.cache_limit.
        Also, it will return None on input 0

        INPUT:
        n -- A nonzero long
        OUTPUT:
        A context for p^n

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 6, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'big')
        sage: A._get_context_test(4) #indirect doctest
        NTL modulus 625
        sage: A._get_context_test(8) #indirect doctest
        NTL modulus 390625
        """
        if n == 0:
            raise ValueError, "n must be nonzero"
        if n < 0:
            n = -n
        if n <= self.cache_limit:
            return self.context_list[n]
        elif n == self.prec_cap:
            return self.top_context
        else:
            try:
                return self.context_dict[n]
            except KeyError:
                self.context_dict[n] = PowComputer_ZZ_pX.get_context(self, n)
                return self.context_dict[n]

    cdef ntl_ZZ_pContext_class get_top_context(self):
        """
        Returns a ZZ_pContext for self.prime^self.prec_cap
        
        sage: PC = PowComputer_ext_maker(5, 5, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'big','e',ntl.ZZ_pX([1],5^10))
        sage: PC._get_top_context_test() # indirect doctest
        NTL modulus 9765625
        """        
        return self.top_context

    cdef void restore_top_context(self):
        """
        Restores the context corresponding to self.prime^self.prec_cap

        EXAMPLES:
        sage: PC = PowComputer_ext_maker(5, 5, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'big','e',ntl.ZZ_pX([1],5^10))
        sage: PC._restore_top_context_test() #indirect doctest        
        """
        self.top_context.restore_c()

    cdef ZZ_pX_Modulus_c* get_modulus(self, long n):
        """
        Returns the modulus corresponding to self.polynomial() (mod self.prime^n).

        INPUT:
        n -- A nonzero long

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 3, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'big','e',ntl.ZZ_pX([1],5^10))
        sage: a = ntl.ZZ_pX([4,2],5^2)
        sage: b = ntl.ZZ_pX([6,3],5^2)
        sage: A._get_modulus_test(a, b, 2) # indirect doctest
        [4 24]
        sage: a = ntl.ZZ_pX([4,2],5^6)
        sage: b = ntl.ZZ_pX([6,3],5^6)
        sage: A._get_modulus_test(a, b, 6) # indirect doctest
        [54 24]
        sage: A._get_modulus_test(a, b, 6) # indirect doctest
        [54 24]
        """
        cdef ntl_ZZ_pX tmp
        cdef ntl_ZZ_pX_Modulus holder
        cdef ntl_ZZ_pContext_class c
        if n == 0:
            raise ValueError, "n must be nonzero"
        if n < 0:
            n = -n
        elif n <= self.cache_limit:
            return &(self.modulus_list[n])
        elif n == self.prec_cap:
            return &self.top_mod
        else:
            if self.modulus_dict.has_key(n):
                return &((<ntl_ZZ_pX_Modulus>self.modulus_dict[n]).x)
            else:
                c = self.get_context(n)
                c.restore_c()
                tmp = PY_NEW(ntl_ZZ_pX)
                tmp.c = c
                ZZ_pX_conv_modulus(tmp.x, self.top_mod.val(), c.x)
                holder = ntl_ZZ_pX_Modulus(tmp)
                self.modulus_dict[n] = holder
                return &(holder.x)

    cdef ZZ_pX_Modulus_c* get_top_modulus(self):
        """
        Returns the modulus corresponding to self.polynomial() (mod self.prime^self.prec_cap)

        EXAMPLES:
        sage: A = PowComputer_ext_maker(5, 5, 10, 20, False, ntl.ZZ_pX([-5,0,1],5^10), 'big','e',ntl.ZZ_pX([1],5^10))
        sage: a = ntl.ZZ_pX([129223,1231],5^10)
        sage: b = ntl.ZZ_pX([289741,323],5^10)
        sage: A._get_top_modulus_test(a, b) #indirect doctest
        [1783058 7785200]         
        """
        return &self.top_mod

cdef class PowComputer_ZZ_pX_big_Eis(PowComputer_ZZ_pX_big):
    """
    This class computes and stores low_shifter and high_shifter, which aid in right shifting elements.
    These are only stored at maximal precision: in order to get lower precision versions just reduce mod p^n.
    """
    def __new__(self, Integer prime, long cache_limit, long prec_cap, long ram_prec_cap, bint in_field, poly, shift_seed = None):
        self._ext_type = 'e'
        if not PY_TYPE_CHECK(shift_seed, ntl_ZZ_pX):
            raise TypeError, "shift_seed must be an ntl_ZZ_pX"
        ZZ_pX_Eis_init(self, <ntl_ZZ_pX>shift_seed)
    
    def _low_shifter(self, i):
        cdef long _i = i
        cdef ntl_ZZ_pX ans
        if _i >= 0 and _i < self.low_length:
            ans = ntl_ZZ_pX([], self.get_top_context())
            ans.x = self.low_shifter[i]
            return ans
        else:
            raise IndexError

    def _high_shifter(self, i):
        cdef long _i = i
        cdef ntl_ZZ_pX ans
        if _i >= 0 and _i < self.high_length:
            ans = ntl_ZZ_pX([], self.get_top_context())
            ans.x = self.high_shifter[i]
            return ans
        else:
            raise IndexError
                    

    def __dealloc__(self):
        if self._initialized:
            self.cleanup_ZZ_pX_big_Eis()

    cdef void cleanup_ZZ_pX_big_Eis(self):
        #pass
        # I may or may not need to deallocate these:
        #
        cdef int i # yes, an int is good enough
        for i from 0 <= i < self.low_length:
            ZZ_pX_destruct(&(self.low_shifter[i]))
        sage_free(self.low_shifter)
        for i from 0 <= i < self.high_length:
            ZZ_pX_destruct(&(self.high_shifter[i]))
        sage_free(self.high_shifter)

    cdef int eis_shift(self, ZZ_pX_c* x, ZZ_pX_c* a, long n, long finalprec) except -1:
        return ZZ_pX_eis_shift(self, x, a, n, finalprec)

def PowComputer_ext_maker(prime, cache_limit, prec_cap, ram_prec_cap, in_field, poly, prec_type = "small", ext_type = "u", shift_seed = None):
    """
    Returns a PowComputer that caches the values $1, prime, prime^2, \ldots, prime^cache_limit$.

    Once you create a PowComputer, merely call it to get values out.
    You can input any integer, even if it's outside of the precomputed range.

    INPUT:
    prime -- An integer, the base that you want to exponentiate.
    cache_limit -- A positive integer that you want to cache powers up to.
    prec_cap -- The cap on precisions of elements.  For ramified extensions,
                p^((prec_cap - 1) // e) will be the largest power of p distinguishable
                from zero
    in_field -- Boolean indicating whether this PowComputer is attached to a field or not.
    poly -- An ntl_ZZ_pX or ntl_ZZ_pEX defining the extension.  It should be defined modulo
                p^((prec_cap - 1) // e + 1)
    prec_type -- 'FM', 'small', or 'big', defining how caching is done.
    ext_type -- 'u' = unramified, 'e' = eisenstein, 't' = two-step
    shift_seed -- (required only for eisenstein and two-step) For eisenstein and two-step extensions, if f = a_n x^n - p a_{n-1} x^{n-1} - ... - p a_0
                with a_n a unit, then shift_seed should be 1/a_n (a_{n-1} x^{n-1} + ... + a_0)
                
    EXAMPLES:
    sage: PC = PowComputer_ext_maker(5, 10, 10, 20, False, ntl.ZZ_pX([-5, 0, 1], 5^10), 'small','e',ntl.ZZ_pX([1],5^10))
    sage: PC
    PowComputer_ext for 5, with polynomial [9765620 0 1]
    """
    cdef Integer _prime = <Integer>Integer(prime)
    cdef long _cache_limit = mpz_get_si((<Integer>Integer(cache_limit)).value)
    cdef long _prec_cap = mpz_get_si((<Integer>Integer(prec_cap)).value)
    cdef long _ram_prec_cap = mpz_get_si((<Integer>Integer(ram_prec_cap)).value)
    cdef bint inf = in_field
    if ext_type != "u" and shift_seed is None:
        raise ValueError, "must provide shift seed"
    if prec_type == "small" and ext_type == "u":
        return PowComputer_ZZ_pX_small(_prime, _cache_limit, _prec_cap, _ram_prec_cap, inf, poly, None)
    elif prec_type == "small" and ext_type == "e":
        return PowComputer_ZZ_pX_small_Eis(_prime, _cache_limit, _prec_cap, _ram_prec_cap, inf, poly, shift_seed)
    elif prec_type == "big" and ext_type == "u":
        return PowComputer_ZZ_pX_big(_prime, _cache_limit, _prec_cap, _ram_prec_cap, inf, poly, None)
    elif prec_type == "big" and ext_type == "e":
        return PowComputer_ZZ_pX_big_Eis(_prime, _cache_limit, _prec_cap, _ram_prec_cap, inf, poly, shift_seed)
    elif prec_type == "FM" and ext_type == "u":
        return PowComputer_ZZ_pX_FM(_prime, _cache_limit, _prec_cap, _ram_prec_cap, inf, poly, None)
    elif prec_type == "FM" and ext_type == "e":
        return PowComputer_ZZ_pX_FM_Eis(_prime, _cache_limit, _prec_cap, _ram_prec_cap, inf, poly, shift_seed)
    else:
        raise ValueError, "prec_type must be one of 'small', 'big' or 'FM' and ext_type must be one of 'u' or 'e' or 't'"

