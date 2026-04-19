from configparser import ConfigParser
import os


class LocalProfile:
	def __init__(self, profileDir):
		self.dir = profileDir

		editable = ConfigParser()
		editable.read(os.path.join(profileDir, 'Editable.ini'))
		self.displayName = editable['Editable']['DisplayName']
		self.scoreTag = editable['Editable']['LastUsedHighScoreName']


class LocalProfiles:
	def __init__(self, itgmaniaDir):
		self.profilesDir = os.path.join(itgmaniaDir, 'Save\\LocalProfiles')

	def __iter__(self):
		for profileNum in os.listdir(self.profilesDir):
			profileDir = os.path.join(self.profilesDir, profileNum)
			if not os.path.isdir(profileDir):
				continue
			yield LocalProfile(profileDir)