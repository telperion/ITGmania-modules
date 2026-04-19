import json
import os
from pathlib import Path



def ex2spRatio(expct):
	powBase = 40.0
	inflect = 40.0
	return 0.01*(
		100.0 *
		(pow(powBase, expct/inflect) - 1) /
		(pow(powBase, 100.0/inflect) - 1)
	)
def ex2ep(expct):
	if expct == 100:
		return 1000
	cutoffEP = 85.0
	exClamp = (expct - cutoffEP) if (expct > cutoffEP) else 0
	return int((pow(100, exClamp / (100.0 - cutoffEP)) - 1) * (1000.0 / 99.0))

class Song:
	def __init__(self, hsh, path, entry):
		self.hsh = hsh
		pathParts = Path(path).parts
		self.path = '\\'.join(pathParts[-2:])

		self.clearType = entry['clearType']
		self.date = entry['date']
		self.ex = entry['ex']*0.01
		self.ep = ex2ep(self.ex)
		self.maxPoints = entry['maxPoints']
		self.maxScoringPoints = entry['maxScoringPoints']
		self.passingPoints = entry['passingPoints']
		self.points = entry['points']
		self.rating = int(pathParts[-1][1:3])

		

EP_COUNTS = {
	7: 5,
	8: 5,
	9: 5,
	10: 5,
	11: 5,
	12: 4,
	13: 3,
	14: 2,
	15: 1,
}

class ITLData:
	def __init__(self, jsonPath):
		self.hashes = {}
		self.paths = {}
		with open(jsonPath) as f:
			itlData = json.loads(f.read())
			for path, hsh in itlData['pathMap'].items():
				song = Song(hsh, path, itlData['hashMap'][hsh])
				self.paths[path] = song
				self.hashes[hsh] = song

		self.songs = sorted(list(self.paths.values()), key=lambda x: x.points, reverse=True)
		self.exTrapezoid = {rating: [] for rating in EP_COUNTS}
		for song in self.songs:
			self.exTrapezoid[song.rating].append(song)
		for rating in EP_COUNTS:
			self.exTrapezoid[rating].sort(key=lambda x: x.ex, reverse=True)
			count = EP_COUNTS[rating]
			self.exTrapezoid[rating] = self.exTrapezoid[rating][:count]


	def top75(self):
		return self.songs[:75]

	def floorSP(self):
		if len(self.songs) < 75:
			return 0
		return self.songs[74].points

	def floorEPEX(self, rating):
		if rating not in EP_COUNTS:
			return 100
		if len(self.exTrapezoid[rating]) < EP_COUNTS[rating]:
			return 0
		return self.exTrapezoid[rating][-1].ex

	def currentSP(self):
		return sum(x.points for x in self.top75())

	def currentEP(self):
		return sum(sum(song.ep for song in row) for row in self.exTrapezoid.values())

