#!/usr/bin/env python
import optparse
# Import BeautifulSoup -- try 4 first, then fall back to older
try:
	from bs4 import BeautifulSoup
except ImportError:
	try:
		from BeautifulSoup import BeautifulSoup
	except:
		print('Must first install BeautifulSoup ... Sorry!')
		sys.exit(1)

def main():
	# add options to the option parser
	parser = optparse.OptionParser()
	parser.add_option('-a', '--apar-id',
	                  default = None,
	                  action = 'store_true',
	                  help = 'Print the APAR id.')
	parser.add_option('-A', '--apar-abstract',
	                  default = None,
	                  action = 'store_true',
	                  help = 'Print the APAR abstract summary.')

	# parse options, arguments
	options, args = parser.parse_args()
	del parser

	div_id_dict = {
		'apar_id' : 'cq_widget_CqFormEdit_0',
		'component_id' : 'cq_widget_CqFormEdit_1'
	}

	url = sys.argv[1]
	html = build_opener(HTTPCookieProcessor(CookieJar())).open(Request(url=url, headers={'User-Agent': USER_AGENT})).read()
	soup = BeautifulSoup(html)

if __name__ == '__main__':
	main()
