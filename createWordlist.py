#!/bin/python3

import re, signal, sys, atexit
from pwn import *

def ctrlC(sig, frame):
    log.failure("Exit...")
    os.remove("./wordlist.txt")
    sys.exit(1)

signal.signal(signal.SIGINT, ctrlC)


def help():
	print()
	log.info("Use: " + sys.argv[0] + " File")
	sys.exit(1)

def createUser(user):
	usernames = []
	name = user[0].casefold()
	surname = user[1].casefold()

	usernames.append(name[0] + surname + "\n")
	usernames.append(name[0] + "." + surname + "\n")
	usernames.append(name + "\n")
	usernames.append(surname + "\n")
	usernames.append(name + "." + surname + "\n")
	usernames.append(name + surname + "\n")
	usernames.append(surname[0] + name + "\n")
	usernames.append(surname[0] + "." + name + "\n")

	return usernames

def main():
	if len(sys.argv) != 2:
		help()
	file = sys.argv[1]
	try:
		output = open("wordlist.txt",'x')
	except FileNotFoundError:
		print()
		log.failure("The file %s doesn't exist" % (file) )
		os.remove("wordlist.txt")
		sys.exit(1)
	except FileExistsError: 
		print()
		log.failure("The file wordlist.txt exist")
		print()
		log.info("Removing wordlist.txt")
		os.remove("./wordlist.txt")
		output = open("wordlist.txt",'x')

	print()
	log.info("Creating Wordlist")
	with open(file) as f:
		for user in f.readlines():
			usernames = createUser(user.split())
			output.writelines(usernames)
	print()
	log.info("Wordlist Created")
	output.close()
	sys.exit(0)


if __name__ == '__main__':
	main()


