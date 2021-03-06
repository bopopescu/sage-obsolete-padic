cdef extern from "zn_poly/zn_poly.h":
     # This header needs to appear before the flint headers. 
     pass

from sage.libs.flint.zmod_poly cimport zmod_poly_t, zmod_poly_struct
from sage.structure.parent cimport Parent

ctypedef zmod_poly_struct celement
ctypedef unsigned long cparent

include "polynomial_template_header.pxi"

cdef cparent get_cparent(parent) except? 0

cdef class Polynomial_zmod_flint(Polynomial_template):
    cdef Polynomial_template _new(self)
    cdef _set_list(self, x)
    cpdef _mul_trunc(self, Polynomial_zmod_flint other, length)
    cpdef _mul_trunc_opposite(self, Polynomial_zmod_flint other, length)
    cpdef rational_reconstruct(self, m, n_deg=?, d_deg=?)
    
