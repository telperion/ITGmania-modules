from itldata import ITLData
from localprofiles import LocalProfiles
import os
from scobility import Scobility


scooby = Scobility()

for profile in LocalProfiles('C:\\Games\\ITGmania'):
	itlJson = os.path.join(profile.dir, 'ITL2026.json')
	if not os.path.isfile(itlJson):
		continue

	print('--------------------------------------')
	print(f'Processing profile named {profile.displayName}...')

	data = ITLData(itlJson)
	currentEP = data.currentEP()
	currentSP = data.currentSP()
	currentRP = currentSP + currentEP
	rpTarget = 75000*(int(currentRP/75000) + 1)
	spTarget = rpTarget - currentEP

	i = 0
	targetPerSong = spTarget/75
	while(i < len(data.songs)) and (targetPerSong < data.songs[i].points):
		song = data.songs[i]
		print(f'{song.points} beats current target {targetPerSong}')
		spTarget -= song.points
		i += 1
		targetPerSong = spTarget / (75 - i)
	print(f'final per-song target: {int(targetPerSong)}')

	mpFloor = min(x.maxPoints for x in data.top75() if x.points > targetPerSong)
	print(f'final max-points floor: {mpFloor}')

	scooby.processPlayer(profile.displayName, data)
	allTargets = []
	targetsByRating = {}
	for song in data.songs:
		if song.potentialRP == 0:
			continue
		allTargets.append(song)
		if song.rating not in targetsByRating:
			targetsByRating[song.rating] = []
		targetsByRating[song.rating].append(song)


	spiceEpCeilings = {rating: (max(song.spice for song in songs) if songs else 0) for rating, songs in data.exTrapezoid.items()}

	targetsByDate = {}
	for song in data.songs:
		if (song.maxPoints > mpFloor) or ((song.rating in spiceEpCeilings) and (song.spice <= spiceEpCeilings[song.rating])):
			date = song.date
			if date:
				passDate = f'Best score from {date[:7]}'
			else:
				passDate = 'Never passed'
			if passDate not in targetsByDate:
				targetsByDate[passDate] = []
			targetsByDate[passDate].append(song)

	playlistLines = []
	playlistLines.append("---All +RP")
	for target in sorted(allTargets, reverse=True, key=lambda x: x.potentialRP):
		playlistLines.append(target.path)
	for rating in sorted(targetsByRating.keys()):
		minRP = min(x.potentialRP for x in targetsByRating[rating])
		maxRP = max(x.potentialRP for x in targetsByRating[rating])
		if minRP == maxRP:
			playlistLines.append(f'---[{rating:02}] +{minRP} RP')
		else:
			playlistLines.append(f'---[{rating:02}] +{minRP}-{maxRP} RP')
		playlistLines += [x.path for x in sorted(targetsByRating[rating], reverse=True, key=lambda x:x.potentialRP)]

	for passDate in sorted(targetsByDate.keys()):
		playlistLines.append(f'---{passDate}')
		for target in sorted(targetsByDate[passDate], key=lambda x: x.maxPoints):
			playlistLines.append(target.path)

	PLAYLISTS_DIR = os.path.join(profile.dir, 'Playlists')
	if not os.path.isdir(PLAYLISTS_DIR):
		os.mkdir(PLAYLISTS_DIR)
	with open(os.path.join(profile.dir, f'Playlists\\ITL - {profile.displayName}.txt'), 'w') as f:
		f.write('\n'.join(playlistLines))

