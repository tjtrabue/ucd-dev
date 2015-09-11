#!/usr/bin/env python
import re, sys

def main():
	for line in sys.stdin:
		line = re.sub(r'({|}|\[|\])\s+', r'\1', line)
		line = re.sub(r'(?P<prop>[^,\[{:]+):\s+', r'"\g<prop>": ', line)
		line = re.sub(r':\s+([^"]+),\s+"', r': "\1",\n"', line)
		line = re.sub(r',"\s+', r',"', line)
		line = re.sub(r'":\s*(?P<desc>([^\[{]+?(\${.+?})?)+?)(?P<end>,"|})', r'":"\g<desc>"\g<end>', line)
		line = re.sub(r'\s+"(,|}|\])', r'"\1', line)
		print line

if __name__ == '__main__':
	main()
