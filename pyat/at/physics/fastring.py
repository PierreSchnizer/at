"""
Functions relating to fast_ring
"""
import numpy
from math import sqrt, atan2, pi

import scipy.stats
from at.lattice import uint32_refpts, get_refpts, get_cells, checktype
from at.lattice import Element, RFCavity, Marker, Drift
from at.physics import find_orbit6, find_orbit4
from at.physics import gen_m66_elem, gen_detuning_elem, gen_quantdiff_elem

__all__ = ['fast_ring']


def rearrange(ring, split_inds=None):
    limits=[0]+list(uint32_refpts(split_inds, len(ring))) + [len(ring)+1]
    all_rings = [ring[ibeg:iend]
                 for ibeg, iend in zip(limits[:-1], limits[1:])]

    for ring_slice in all_rings:
        # replace cavity with length > 0 with drift
        # set cavity length to 0 and move to start
        cavpts = uint32_refpts(get_cells(ring, checktype(RFCavity)), len(ring))
        cavities = []
        for cavindex in reversed(cavpts):
            cavity = ring_slice.pop(cavindex)
            if cavity.Length != 0:
                ring_slice.insert(cavindex, Drift('CavDrift', cavity.Length))
                cavity.Length = 0.0
            cavities.append(cavity)

        # merge all cavities with the same frequency
        freqs = numpy.array([cav.Frequency for cav in cavities])
        volts = numpy.array([cav.Voltage for cav in cavities])
        _, id, iv = numpy.unique(freqs, return_index=True, return_inverse=True)

        ring_slice.insert(0, Marker('xbeg'))
        for ires, icav in enumerate(id):
            cav=cavities[icav]
            cav.Voltage = sum([volts[iv==ires]])
            ring_slice.insert(0, cav)
        ring_slice.append(Marker('xend'))

    return all_rings


def merge_rings(all_rings):
    ringnorad = all_rings[0]
    if len(all_rings) > 1:
        for ringi in all_rings[1:]:
            ringnorad += ringi
    ringrad = ringnorad.deepcopy()
    if ringnorad.radiation:
        ringnorad.radiation_off(quadrupole_pass='auto')
    else:
        ringrad.radiation_on(quadrupole_pass='auto')
    return ringnorad, ringrad


def fast_ring(ring, split_inds=None):
    if not ring.radiation:
        ring=ring.radiation_on(copy=True)
    all_rings = rearrange(ring, split_inds=split_inds)
    ringnorad, ringrad = merge_rings(all_rings)

    ibegs = get_refpts(ringnorad, 'xbeg')
    iends = get_refpts(ringnorad, 'xend')
    markers = numpy.sort(numpy.concatenate((ibegs, iends)))

    _, orbit4 = ringnorad.find_sync_orbit(dct=0.0, refpts=markers)
    _, orbit6 = ringrad.find_orbit6(refpts=markers)

    detuning_elem = gen_detuning_elem(ringnorad, orbit4[-1])
    detuning_elem_rad = detuning_elem.deepcopy()
    detuning_elem_rad.T1 = -orbit6[-1]
    detuning_elem_rad.T2 = orbit6[-1]

    for counter, ring_slice in enumerate(all_rings):

        ibeg = get_refpts(ring_slice, 'xbeg')[0]
        iend = get_refpts(ring_slice, 'xend')[0]
        cavs = ring_slice[:ibeg]
        ring_slice = ring_slice[ibeg:iend]
        ring_slice_rad = ring_slice.deepcopy()

        if ring_slice.radiation:
            ring_slice.radiation_off(quadrupole_pass='auto')
        else:
            ring_slice_rad.radiation_on(quadrupole_pass='auto')

        lin_elem = gen_m66_elem(ring_slice, orbit4[2*counter],
                                orbit4[2*counter+1])
        lin_elem.FamName = lin_elem.FamName + '_' + str(counter)

        qd_elem = gen_quantdiff_elem(ring_slice_rad, orbit=orbit6[2*counter])
        qd_elem.FamName = qd_elem.FamName + '_' + str(counter)
        lin_elem_rad = gen_m66_elem(ring_slice_rad, orbit6[2*counter],
                                    orbit6[2*counter+1])
        lin_elem_rad.FamName = lin_elem_rad.FamName + '_' + str(counter)

        [ringnorad.append(cav) for cav in cavs]
        ringnorad.append(lin_elem)
        [ringrad.append(cav) for cav in cavs]
        ringrad.append(lin_elem_rad)
        ringrad.append(qd_elem)

    ringnorad.append(detuning_elem)
    ringrad.append(detuning_elem_rad)
    del ringnorad[:markers[-1]+1]
    del ringrad[:markers[-1]+1]

    return ringnorad, ringrad
