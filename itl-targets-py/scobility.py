import json
import math
import requests


POW_BASE = 40.0
INFLECT = 40.0
CUTOFF_EP = 85.0
def EX2SP(expct):
	return (
		100.0 *
		(pow(POW_BASE, expct/INFLECT) - 1) /
		(pow(POW_BASE, 100.0/INFLECT) - 1)
	)
def SP2EX(sppct):
	centuryScale = 100.0 / (pow(POW_BASE, 100.0/INFLECT) - 1)
	return (
		INFLECT *
		math.log(sppct/centuryScale + 1) /
		math.log(POW_BASE)
	)
def EX2EP(expct):
	exClamp = (expct - CUTOFF_EP) if (expct > CUTOFF_EP) else 0
	return min(1000, math.floor((pow(100, exClamp / (100.0 - CUTOFF_EP)) - 1) * (1000.0 / 99.0)))

def dumbassLSQComponents(a, b):
	s, s2, q, sq = 0, 0, 0, 0
	for i, va in enumerate(a):
		vb = b[i]
		s += va
		s2 += (va*va)
		q += vb
		sq += (va*vb)
	return len(a), s, s2, q, sq

def dumbassLSQFree(a, b):
	ones, s, s2, q, sq = dumbassLSQComponents(a, b)
	det = ones*s2 - s*s
	c1 = (-s*q + ones*sq)/det
	c0 = (s2*q - s*sq)/det
	residual = 0
	for i, va in enumerate(a):
		vb = b[i]
		vr = vb - (c1*va + c0)
		residual = residual + vr*vr
	return c0, c1, residual

def dumbassLSQWithCutPoint(a, b, anchor):
	al = a[:anchor]
	ar = a[anchor:]
	bl = b[:anchor]
	br = b[anchor:]
	if len(al) < 2 or len(ar) < 2:
		return None

	c0l, c1l, resl = dumbassLSQFree(al, bl)
	c0r, c1r, resr = dumbassLSQFree(ar, br)
	horizonSpice = (c1r - c1l)/(c0l - c0r)
	horizonQuality = c1l*horizonSpice + c0l
	timingPower = c0l if (horizonSpice > 0) else c0r
	return {
		"cutPoint": anchor,
		"timingPower": timingPower,
		"horizonSpice": horizonSpice,
		"horizonQuality": horizonQuality,
		"mildSlope": c1l,
		"hotSlope": c1r,
		"residual": resl + resr,
	}

def dumbassLSQAnchored(a, b, anchor):
	k = a[anchor]
	aOffset = []
	ones = len(a)
	q = 0
	for i, v in enumerate(a):
		aOffset.append(v - k)
		q += b[i]

	al = aOffset[:anchor]
	ar = aOffset[anchor:]
	bl = b[:anchor]
	br = b[anchor:]
	if len(al) < 2 or len(ar) < 2:
		return None

	onesl, sl, s2l, ql, sql = dumbassLSQComponents(al, bl)
	onesr, sr, s2r, qr, sqr = dumbassLSQComponents(ar, br)

	m11 = ones*s2r - sr*sr
	m12 = sl*sr
	m13 = -sl*s2r
	m22 = ones*s2l - sl*sl
	m23 = -s2l*sr
	m33 = s2l*s2r
	det = ones*s2r*s2l - sr*sr*s2l - sl*sl*s2r

	c1l = (m11*sql + m12*sqr + m13*q)/det
	c1r = (m12*sql + m22*sqr + m23*q)/det
	c0 = (m13*sql + m23*sqr + m33*q)/det

	residual = 0
	for i, va in enumerate(aOffset):
		vb = b[i]
		c1choice = c1l if (i < anchor) else c1r
		vr = vb - (c1choice*va + c0)
		residual += vr*vr

	return {
		"c0": c0,
		"c1l": c1l,
		"c1r": c1r,
		"residual": residual,
	}

def spiceHorizonFit(a, b):
	best = None
	horizonCentering = math.floor(math.sqrt(len(a)))

	for j in range(horizonCentering, len(a) - horizonCentering + 1):
		bestFitHere = dumbassLSQWithCutPoint(a, b, j)
		if (not bestFitHere) or (bestFitHere["horizonSpice"] < a[j]) or (bestFitHere["horizonSpice"] > a[j+1]):
			bestFitHereL = dumbassLSQAnchored(a, b, j)
			bestFitHereR = dumbassLSQAnchored(a, b, j+1)
			if bestFitHereL and bestFitHereR:
				if bestFitHereL["residual"] < bestFitHereR["residual"]:
					bestFitHere = {
						"cutPoint": j,
						"horizonSpice": a[j],
						"horizonQuality": bestFitHereL["c0"],
						"mildSlope": bestFitHereL["c1l"],
						"hotSlope": bestFitHereL["c1r"],
						"timingPower": bestFitHereL["c0"] - bestFitHereL["c1l"]*a[j],
						"residual": bestFitHereL["residual"],
					}
				else:
					bestFitHere = {
						"cutPoint": j,
						"horizonSpice": a[j+1],
						"horizonQuality": bestFitHereR["c0"],
						"mildSlope": bestFitHereR["c1l"],
						"hotSlope": bestFitHereR["c1r"],
						"timingPower": bestFitHereR["c0"] - bestFitHereR["c1l"]*a[j+1],
						"residual": bestFitHereR["residual"],
					}

		if bestFitHere and ((not best) or (bestFitHere["residual"] < best["residual"])):
			best = bestFitHere

	return best


PERFECT_OFFSET = 1.003

class Scobility:
	def __init__(self):
		response = requests.get("https://scobility.azurewebsites.net/catalog/ITL2026/chart/all")
		self.spice = {hsh: math.log2(entry['spice']) for hsh, entry in json.loads(response.text)['data'].items() if entry['spice'] is not None}
		self.playerData = {}

	def processPlayer(self, playerKey, itlData):
		self.playerData[playerKey] = itlData
		for hsh, song in itlData.hashes.items():
			if (song.clearType > 0) and (hsh in self.spice):
				song.spice = self.spice[hsh]
				song.quality = (
					self.spice[hsh] -
					math.log2(PERFECT_OFFSET - song.ex*0.01)
				)
		spiceSort = sorted(itlData.songs, key=lambda s: s.spice)
		coefs = spiceHorizonFit([x.spice for x in spiceSort], [x.quality for x in spiceSort])
		itlData.cutPoint = coefs["cutPoint"]
		itlData.horizonSpice = coefs["horizonSpice"]
		itlData.horizonQuality = coefs["horizonQuality"]
		itlData.mildSlope = coefs["mildSlope"]
		itlData.hotSlope = coefs["hotSlope"]
		itlData.timingPower = coefs["timingPower"]
		itlData.residual = coefs["residual"]


		for hsh, song in itlData.hashes.items():
			if song.spice <= itlData.horizonSpice:
				qualityFit = itlData.mildSlope*(song.spice - itlData.horizonSpice) + itlData.horizonQuality
			else:
				qualityFit = itlData.hotSlope*(song.spice - itlData.horizonSpice) + itlData.horizonQuality

			targetEX = 100.0*(PERFECT_OFFSET - pow(2, song.spice - qualityFit))
			if targetEX > 100:
				targetEX = 100
			if targetEX < 0:
				targetEX = 0
			else:
				targetEX = math.floor(targetEX*100 + 0.5)*0.01

			targetSP = math.floor(song.passingPoints + song.maxScoringPoints*EX2SP(targetEX)*0.01)
			targetEP = 1000 if (targetEX == 100) else EX2EP(targetEX)
			if any(s.hsh == hsh for s in itlData.top75()):
				song.potentialSP = targetSP - song.points
			else:
				song.potentialSP = targetSP - itlData.floorSP()
			if song.potentialSP < 0:
				song.potentialSP = 0

			if song.rating not in itlData.exTrapezoid:
				song.potentialEP = 0
			elif any(s.hsh == hsh for s in itlData.exTrapezoid[song.rating]):
				song.potentialEP = targetEP - EX2EP(song.ex)
			else:
				song.potentialEP = targetEP - EX2EP(itlData.floorEPEX(song.rating))
			if song.potentialEP < 0:
				song.potentialEP = 0

			song.potentialRP = song.potentialSP + song.potentialEP