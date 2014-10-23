class DataSet {
	protected XmlDocument _docroot;
	protected string _name;
	protected string[string] _attributes;
	protected DataSet[]      _children;



	static this(){}

	/// Construct an empty DataSet.
	this(){}

	/// Construct and set the name of this DataSet.
	this(string name) {
		_name = name;
	}

	/// Get the name of this DataSet.
	string getName() {
		return _name;
	}

	/// Set the name of this DataSet.
	void setName(string newName) {
		_name = newName;
	}

	/// Does this DataSet have the specified attribute?
	bool hasAttribute(string name) {
		return (name in _attributes) !is null;
	}

	/// Get the specified attribute, or return null if the DataSet doesn't have that attribute.
	string getAttribute(string name) {
		if (name in _attributes)
			return xmlDecode(_attributes[name]);
		else
			return null;
	}

	/// Return an array of all attributes (does a single pass of XML entity decoding like &quot; -> ").
	string[string] getAttributes() {
		string[string]tmp;
		// this is inefficient as it is run every time, but doesn't hurt parsing speed
		foreach(key;_attributes.keys) {
			tmp[key] = xmlDecode(_attributes[key]);
		}
		return tmp;
	}

	/// Set an attribute to a string value.
	/// The attribute is created if it doesn't exist.
	DataSet setAttribute(string name, string value) {
		_attributes[name] = xmlEncode(value);
		return this;
	}

	/// Set an attribute to an integer value (stored internally as a string).
	/// The attribute is created if it doesn't exist.
	DataSet setAttribute(string name, long value) {
		return setAttribute(name, tostring(value));
	}

	/// Set an attribute to a float value (stored internally as a string).
	/// The attribute is created if it doesn't exist.
	DataSet setAttribute(string name, float value) {
		return setAttribute(name, tostring(value));
	}

	/// Remove the attribute with name.
	DataSet removeAttribute(string name) {
		_attributes.remove(name);
		return this;
	}

	/// Add a child node.
	DataSet addChild(DataSet newNode) {
		// let's bump things by increments of 10 to make them more efficient
		if (_children.length+1%10==0) {
			_children.length = _children.length + 10;
			_children.length = _children.length - 10;
		}
		_children.length = _children.length + 1;
		_children[$-1] = newNode;
		return this;
	}

	/// Get all child nodes associated with this object.
	/// Returns: An raw, uncopied array of all child nodes.
	DataSet[] getChildren() {
		return _children;
	}

	/// Remove the child with the same reference as what was given.
	/// Returns: The number of children removed.
	size_t removeChild(DataSet remove) {
		size_t len = _children.length;
		for (size_t i = 0;i<_children.length;i++) if (_children[i] is remove) {
			// we matched it, so remove it
			// don't return true yet, since we're removing all references to it, not just the first one
			_children = _children[0..i]~_children[i+1..$];
		}
		return len - _children.length;
	}

	/// Add a child Node of cdata (text).
	DataSet addCData(string cdata) {
		auto cd = (_docroot?_docroot.allocCData:new CData);
		cd.setCData(cdata);
		addChild(cd);
		return this;
	}

	/// Check to see if this node is a CData node.
	final bool isCData() {
		if (cast(CData)this) return true;
		return false;
	}

	/// Check to see if this node is a XmlPI node.
	final bool isXmlPI() {
		if (cast(XmlPI)this) return true;
		return false;
	}

	/// Check to see if this node is a XmlComment node.
	final bool isXmlComment() {
		if (cast(XmlComment)this) return true;
		return false;
	}

	/// This function makes life easier for those looking to pull cdata from a tag, in the case of multiple nodes, it pulls all first level cdata nodes.
	string getCData() {
		string tmp;
		foreach(child;_children) if (child.isCData) {
			tmp ~= child.getCData(); 
		}
		return tmp;
	}

	/// This function resets the node to a default state
	void reset() {
		foreach(child;_children) {
			child.reset;
		}
		_children.length = 0;
		_attributes = null;
		_name = null;
		// put back in the pool of available DataSet nodes if possible
		if (_docroot) {
			_docroot.xmlNodes.length = _docroot.xmlNodes.length + 1;
			_docroot.xmlNodes[$-1] = this;
		}
	}

	/// This function removes all child nodes from the current node
	DataSet removeChildren() {
		_children.length = 0;
		return this;
	}

	/// This function sets the cdata inside the current node as intelligently as possible (without allocation, hopefully)
	DataSet setCData(string cdata) {
		if (_children.length == 1 && _children[0].isCData) {
			// since the only node is CData, just set the text and be done
			_children[0].setCData(cdata);
		} else {
			removeChildren;
			addCData(cdata);
		}
		return this;
	}

	/// This function gives you the inner xml as it would appear in the document.
	string getInnerXML() {
		string tmp;
		foreach(child;_children) {
			tmp ~= child.toString(); 
		}
		return tmp;
	}

	// internal function to generate opening tags
	string asOpenTag() {
		if (_name.length == 0) {
			return null;
		}
		auto s = "<" ~ _name ~ genAttrString();

		if (_children.length == 0)
			s ~= " /"; // We want <blah /> if the node has no children.
		s ~= ">";

		return s;
	}

	// internal function used to generate the attribute list
	protected string genAttrString() {
		string ret;
		foreach (keys,values;_attributes) {
				ret ~= " " ~ keys ~ "=\"" ~ values ~ "\"";
		}
		return ret;
	}

	// internal function to generate closing tags
	string asCloseTag() {
		if (_name.length == 0) {
			return null;
		}
		if (_children.length != 0)
			return "</" ~ _name ~ ">";
		else
			return null; // don't need it.  Leaves close themselves via the <blah /> syntax.
	}

	final protected bool isLeaf() {
		return _children.length == 0;
	}

	/// This function dumps the xml structure to a string with no newlines and no linefeeds to be output.
	override string toString() {
		auto tmp = asOpenTag();

		if (_children.length) {
			tmp ~= getInnerXML();
			tmp ~= asCloseTag();
		}
		return tmp;
	}

	/// This is the old pretty string output function.  It is deprecated in favor of toPrettyString.
	deprecated string write(string indent=null) {
		return toPrettyString(indent);
	}

	/// This function dumps the xml structure in to pretty, tabbed format.
	string toPrettyString(string indent=null) {
		string tmp;
		if (getName.length) tmp = indent~asOpenTag()~"\n";

		if (_children.length)
		{
			for (int i = 0; i < _children.length; i++)
			{
				// these guys are supposed to do their own indentation
				tmp ~= _children[i].toPrettyString(indent~(getName.length?"	":"")); 
			}
			if (getName.length) tmp ~= indent~asCloseTag()~"\n";
		}
		return tmp;
	
	}

	/// Add children from a string containing valid xml.
	void addChildren(string xsrc,bool preserveWS) {
		while (xsrc.length) {
			// there may be multiple tag trees or cdata elements
			parseNode(this,xsrc,preserveWS);
		}
	}

	/// Add array of nodes directly into this node as children.
	void addChildren(DataSet[]newChildren) {
		// let's bump things by increments of 10 to make them more efficient
		if (_children.length+newChildren.length%10 < newChildren.length) {
			_children.length = _children.length + 10;
			_children.length = _children.length - 10;
		}
		_children.length = _children.length + newChildren.length;
		_children[$-newChildren.length..$] = newChildren[0..$];
	}

	// snag some text and lob it into a cdata node
	private void parseCData(DataSet parent,ref string xsrc,bool preserveWS) {
		ptrdiff_t slice;
		string token;
		slice = readUntil(xsrc,"<");
		token = xsrc[0..slice];
		// don't break xml whitespace specs unless requested
		if (!preserveWS) token = stripr(token);
		xsrc = xsrc[slice..$];
		debug(xml)logline("I found cdata text: "~token~"\n");
		// DO NOT CHANGE THIS TO USE THE CONSTRUCTOR, BECAUSE THE CONSTRUCTOR IS FOR USER USE
		auto cd = (_docroot?_docroot.allocCData:new CData);
		cd._cdata = token;
		parent.addChild(cd);
	}

	// parse out a close tag and make sure it's the one we want
	private void parseCloseTag(DataSet parent,ref string xsrc) {
		ptrdiff_t slice;
		string token;
		slice = readUntil(xsrc,">");
		token = strip(xsrc[1..slice]);
		xsrc = xsrc[slice+1..$];
		debug(xml)logline("I found a closing tag (yikes):"~token~"\n");
		if (token.icmp(parent.getName()) != 0) throw new XmlError("Wrong close tag: "~token~" for parent tag "~parent.getName);
	}

	// rip off a xml processing instruction, like the ones that come at the beginning of xml documents
	private void parseXMLPI(DataSet parent,ref string xsrc) {
		// rip off <?
		xsrc = stripl(xsrc[1..$]);
		// rip off name
		string name = getWSToken(xsrc);
		XmlPI newnode;
		if (name[$-1] == '?') {
			// and we're at the end of the element
			name = name[0..$-1];
			newnode = (_docroot?_docroot.allocXmlPI:new XmlPI);
			newnode.setName(name);
			parent.addChild(newnode);
			return;
		}
		// rip off attributes while looking for ?>
		debug(xml)logline("Got a "~name~" XML processing instruction\n");
		newnode = (_docroot?_docroot.allocXmlPI:new XmlPI);
		newnode.setName(name);
		xsrc = stripl(xsrc);
		while(xsrc.length >= 2 && xsrc[0..2] != "?>") {
			parseAttribute(newnode,xsrc);
		}
		// make sure that the ?> is there and rip it off
		if (xsrc[0..2] != "?>") throw new XmlError("Could not find the end to xml processing instruction "~name);
		xsrc = xsrc[2..$];
		parent.addChild(newnode);
	}

	// rip off an unparsed character data node
	private void parseUCData(DataSet parent,ref string xsrc) {
		ptrdiff_t slice;
		string token;
		xsrc = xsrc[7..$];
		slice = readUntil(xsrc,"]]>");
		token = xsrc[0..slice];
		xsrc = xsrc[slice+3..$];
		debug(xml)logline("I found ucdata text: "~token~"\n");
		// DO NOT CHANGE THIS TO USE THE CONSTRUCTOR, BECAUSE THE CONSTRUCTOR IS FOR USER USE
		auto cd = (_docroot?_docroot.allocUCData:new UCData);
		cd._cdata = token;
		parent.addChild(cd);
	}

	// rip off a comment
	private void parseComment(DataSet parent,ref string xsrc) {
		ptrdiff_t slice;
		string token;
		xsrc = xsrc[2..$];
		slice = readUntil(xsrc,"-->");
		token = xsrc[0..slice];
		xsrc = xsrc[slice+3..$];
		auto x = (_docroot?_docroot.allocXmlComment:new XmlComment);
		x._comment = token;
		parent.addChild(x);
	}

	// rip off a XML Instruction
	private void parseXMLInst(DataSet parent,ref string xsrc) {
		ptrdiff_t slice;
		string token;
		slice = readUntil(xsrc,">");
		slice += ">".length;
		if (slice>xsrc.length) slice = xsrc.length;
		token = xsrc[0..slice];
		xsrc = xsrc[slice..$];
		// XXX we probably want to do something with these
	}

	// rip off a XML opening tag
	private void parseOpenTag(DataSet parent,ref string xsrc,bool preserveWS) {
		// rip off name
		string name = getWSToken(xsrc);
		// rip off attributes while looking for ?>
		debug(xml)logline("Got a "~name~" open tag\n");
		auto newnode = (_docroot?_docroot.allocDataSet:new DataSet);
		newnode.setName(name);
		xsrc = stripl(xsrc);
		while(xsrc.length && xsrc[0] != '/' && xsrc[0] != '>') {
			parseAttribute(newnode,xsrc);
		}
		// check for self-closing tag
		parent.addChild(newnode);
		if (xsrc[0] == '/') {
			// strip off the / and go about business as normal
			xsrc = stripl(xsrc[1..$]);
			// check for >
			if (!xsrc.length || xsrc[0] != '>') throw new XmlError("Unable to find end of "~name~" tag");
			xsrc = stripl(xsrc[1..$]);
			debug(xml)logline("self-closing tag!\n");
			return;
		} 
		// check for >
		if (!xsrc.length || xsrc[0] != '>') throw new XmlError("Unable to find end of "~name~" tag");
		xsrc = xsrc[1..$];
		// don't rape whitespace unless requested
		if (!preserveWS) xsrc = stripl(xsrc);
		// now that we've added all the attributes to the node, pass the rest of the string and the current node to the next node
		int ret;
		while (xsrc.length) {
			if ((ret = parseNode(newnode,xsrc,preserveWS)) == 1) {
				break;
			}
		}
		// make sure we found our closing tag
		// this is where we can get sloppy for stream parsing
		// throw a missing closing tag exception
		if (!ret) throw new XmlError("Missing end tag for "~name);
	}

	// returns everything after the first node TREE (a node can be text as well)
	private int parseNode(DataSet parent,ref string xsrc,bool preserveWS) {
		// if it was just whitespace and no more text or tags, make sure that's covered
		int ret = 0;
		// this has been removed from normal code flow to be XML std compliant, preserve whitespace
		if (!preserveWS) xsrc = stripl(xsrc); 
		debug(xml)logline("Parsing text: "~xsrc~"\n");
		if (!xsrc.length) {
			return 0;
		}
		string token;
		if (xsrc[0] != '<') {
			parseCData(parent,xsrc,preserveWS);
			return 0;
		} 
		xsrc = xsrc[1..$];
		
		// types of tags, gotta make sure we find the closing > (or ]]> in the case of ucdata)
		switch(xsrc[0]) {
		default:
			// just a regular old tag
			parseOpenTag(parent,xsrc,preserveWS);
			break;
		case '/':
			// closing tag!
			parseCloseTag(parent,xsrc);
			ret = 1;
			break;
		case '?':
			// processing instruction!
			parseXMLPI(parent,xsrc);
			break;
		case '!':
			xsrc = stripl(xsrc[1..$]);
			// 10 is the magic number that allows for the empty cdata string [CDATA[]]>
			if (xsrc.length >= 10 && xsrc[0..7].cmp("[CDATA[") == 0) {
				// unparsed cdata!
				parseUCData(parent,xsrc);
				break;
			// make sure we parse out comments, minimum length for this is 7 (<!---->)
			} else if (xsrc.length >= 5 && xsrc[0..2].cmp("--") == 0) {
				parseComment(parent,xsrc);
				break;
			}
			// xml instruction is the default for this case
			parseXMLInst(parent,xsrc);
			break;
		}
		return ret;
	}

	// read data until the delimiter is found, return the index where the delimiter starts
	private ptrdiff_t readUntil(string xsrc, string delim) {
		// the -delim.length is partially optimization and partially avoiding jumping the array bounds
		ptrdiff_t i = xsrc.find(delim);
		// yeah...if we didn't find it, then the whole string is the token :D
		if (i == -1) {
			return xsrc.length;
		}
		return i;
	}

	// basically to get the name off of open tags
	private string getWSToken(ref string input) {
		input = stripl(input);
		int i;
		for(i=0;i<input.length && !isspace(input[i]) && input[i] != '>' && input[i] != '/' && input[i] != '<' && input[i] != '=' && input[i] != '!';i++){}
		auto ret = input[0..i];
		input = input[i..$];
		if (!ret.length) {
			throw new XmlError("Unable to parse token at: "~input);
		}
		return ret;
	}

	// this code is now officially prettified
	private void parseAttribute (DataSet xml,ref string attrstr,string term = null) {
		string ripName(ref string input) {
			int i;
			for(i=0;i < input.length && !isspace(input[i]) && input[i] != '=';i++){}
			auto ret = input[0..i];
			input = input[i..$];
			return ret;
		}
		string ripValue(ref string input) {
			int x;
			char quot = input[0];
			// rip off the starting quote
			input = input[1..$];
			// find the end of the string we want
			for(x = 0;x < input.length && input[x] != quot;x++) {}
			if (x == input.length) {
				throw new XmlError("Missing attribute value terminator for value starting at "~input);
			}
			string tmp = input[0..x];
			// add one to leave off the quote
			input = input[x+1..$];
			return tmp;
		}

		// snag the name from the attribute string
		string value,name = ripName(attrstr);
		attrstr = stripl(attrstr);
		// check for = to make sure the attribute string is kosher
		if (!attrstr.length) throw new XmlError("Unexpected end of attribute string near "~name);
		if (attrstr[0] != '=') throw new XmlError("Missing = in attribute string with name "~name);
		// rip off =
		attrstr = attrstr[1..$];
		attrstr = stripl(attrstr);
		if (attrstr.length) {
			if (attrstr[0] == '"' || attrstr[0] == '\'') {
				value = ripValue(attrstr);
			} else {
				throw new XmlError("Unquoted attribute value for "~xml.getName~", starting at: "~attrstr);
			}
		} else {
			throw new XmlError("Unexpected end of input for attribute "~name~" in node "~xml.getName);
		}
		debug(xml)logline("Got attr "~name~" and value \""~value~"\"\n");
		xml._attributes[name] = value;
		attrstr = stripl(attrstr);
	}

	/// Do an XPath search on this node and return all matching nodes.
	/// This function does not perform any modifications to the tree and so does not support XML mutation.
	DataSet[]parseXPath(string xpath,bool caseSensitive = false) {
		// rip off the leading / if it's there and we're not looking for a deep path
		if (!isDeepPath(xpath) && xpath.length && xpath[0] == '/') xpath = xpath[1..$];
		debug(xpath)logline("Got xpath "~xpath~" in node "~getName~"\n");
		string truncxpath;
		auto nextnode = getNextNode(xpath,truncxpath);
		string predmatch;
		// XXX need to be able to split the attribute match off even when it doesn't have [] around it
		ptrdiff_t offset = nextnode.find("[");
		if (offset != -1) {
			// rip out attribute string
			predmatch = nextnode[offset..$];
			nextnode = nextnode[0..offset];
			debug(xpath)logline("Found predicate chunk: "~predmatch~"\n");
		}
		debug(xpath)logline("Looking for "~nextnode~"\n");
		DataSet[]retarr;
		// search through the children to see if we have a direct match on the next node
		if (!nextnode.length) {
			// we were searching for nodes, and this is one
			debug(xpath)logline("Found a node we want! name is: "~getName~"\n");
			retarr ~= this;
		} else if (nextnode[0] == '@') {
			if( matchXPathPredicate(nextnode, caseSensitive)) {
				auto attr = getWSToken(nextnode)[1..$];
				retarr ~= new CData(getAttribute(attr));
			}
		} else foreach(child;getChildren) if (!child.isCData && !child.isXmlComment && !child.isXmlPI && child.matchXPathPredicate(predmatch,caseSensitive)) {
			if (!nextnode.length || (caseSensitive && child.getName == nextnode) || (!caseSensitive && !child.getName().icmp(nextnode))) {
				// child that matches the search string, pass on the truncated string
				debug(xpath)logline("Sending "~truncxpath~" to "~child.getName~"\n");
				retarr ~= child.parseXPath(truncxpath,caseSensitive);
			}
		}
		// we aren't on us, but check to see if we're looking for a deep path, and delve in accordingly
		// currently this means, the entire tree could be traversed multiple times for a single query...eww
		// and the query // should generate a list of the entire tree, in the order the elements specifically appear
		if (isDeepPath(xpath)) foreach(child;getChildren) if (!child.isCData && !child.isXmlComment && !child.isXmlPI) {
			// throw the exact same xpath at each child
			retarr ~= child.parseXPath(xpath,caseSensitive);
		}
		return retarr;
	}

	private bool matchXPathPredicate(string predstr,bool caseSen) {
		debug(xpath)logline("matching predicate string "~predstr~"\n");
		// strip off the encasing [] if it exists
		if (!predstr.length) {
			return true;
		}
		if (predstr[0] == '[' && predstr[$-1] == ']') {
			predstr = predstr[1..$-1];
		} else if (predstr[0] == '[' || predstr[$-1] == ']') {
			// this seems to be malformed
			throw new XPathError("got malformed predicate match "~predstr~"\n");
		}
		// rip apart the xpath predicate assuming it's node and attribute matches
		string[]predlist;
		// basically, we're splitting on " and " and " or ", but while respecting []
		int bcount = 0;
		ptrdiff_t lslice = 0;
		char quote = '\0';
		foreach (i,c;predstr) {
			// XXX the quote stuff here currently does nothing
			if( quote != '\0' ) {
				if( quote == c ) {
					quote = '\0';
				}
			} else if (c == '\'' || c == '"' ) {
				quote = c;
			} else if (c == '[') {
				bcount++;
			} else if (c == ']') {
				bcount--;
			} else if (bcount == 0 && c == ' ') {
				if (i != lslice) {
					predlist ~= predstr[lslice..i];
				}
				lslice = i+1;
			}
		}
		// tack the last one on
		predlist ~= predstr[lslice..$];
		// length must be odd, otherwise the string is jank
		if (!(predlist.length%2)) throw new XPathError("Encountered a janky predicate: "~predstr);
		// verify that odd numbers are "and" or "or"
		foreach (i,pred;predlist) if (i%2 && pred != "and" && pred != "or") {
			throw new XPathError("Encountered consecutive terms not separated by \"and\" or \"or\" starting at: "~pred);
		} else if (!(i%2) && (pred == "and" || pred == "or")) {
			throw new XPathError("Encountered consecutive joining terms (\"and\" or \"or\") in: "~predstr);
		}
		bool[]res;
		res.length = predlist.length;
		int numOrdTerms = 0;
		debug(xpath)foreach (pred;predlist) {
			logline("Term: "~pred~"\n");
		}
		foreach (i,pred;predlist) if (!(i%2)) {
			debug(xpath)logline("matching on "~pred~"\n");
			bool isattr   = false;		// is elem1 @attribute
			bool verbatim = false;		// is elem2 quoted string
			string elem1;			// Left of comparator
			string comparator;		// null, ">","<","=", ">=","<=","!="
			string elem2;			// right of comparator

			if (pred[0] == '@') {
				isattr = true;
				pred = pred[1..$];
			}
			// TODO XXX check elem1/elem2 is an XPath func()
			elem1 = getWSToken(pred);
			pred = stripl(pred);
			// if there is still data in pred, it's time to look for a comparison operator
			if (pred.length) {
				// figure out what comparison needs to be done
				if (pred.length > 1 && (pred[0] == '<' || pred[0] == '>' || pred[0] == '!') && pred[1] == '=') {
					comparator = pred[0..2];
					pred = pred[2..$];
					pred = stripl(pred);
				} else if (pred[0] == '<' || pred[0] == '>' || pred[0] == '=') {
					comparator = pred[0..1];
					pred = pred[1..$];
					pred = stripl(pred);
				} else {
					throw new XPathError("Could not determine comparator at: "~pred);
				}
				if (pred.length < 2 && !isNumeric(pred[0..1])) { 
					throw new XPathError("Badly formed XPath query: Non-numeric comparands must be quoted ("~pred~")");
				}
				// strip off quotes if necessary
				if (pred[$-1] == '"' && pred[0] == '"') {
					pred = pred[1..$-1];
					verbatim = true;
				} else if (pred[$-1] == '"' || pred[0] == '"') {
					throw new XPathError("Badly formed XPath query: Missing quote ("~pred~")");
				}
			}
			elem2 = pred;
			// check to see if we're doing an attribute match
			// there should be NO zero-length strings this far in
			if (isattr) {
				if (!hasAttribute(elem1)) {
					debug(xpath)logline("could not find attr "~elem1~"\n");
					res[i] = false;
					continue;
				}
				if (!comparator.length) {
					// Just check for existance
					res[i] = true;
					continue;
				}
				res[i] = compareXPathPredicate(elem1, comparator, elem2, getAttribute(elem1), caseSen);
			} else if (elem1 == ".") {
				if (compareXPathPredicate(elem1, comparator, elem2, this.getCData, caseSen)) {
					res[i] = true;
				}
				debug(xpath)if(!res[j]) logline("did not match this node\n");
			} else {
				// assume elem1 is a tag
				foreach(child;getChildren) { 
					if (child.isCData || child.isXmlComment || child.isXmlPI || child.getName != elem1) {
						continue;
					}
				
					if (compareXPathPredicate(elem1, comparator, elem2, child.getCData, caseSen)) {
						res[i] = true;
						break;
					}
				}
			}				
			// XXX take care of other types of matches other than attribute matches
		} else if (pred == "or") {
			numOrdTerms++;
		}
		// collect "and" terms into "or" groups
		bool[]ordTerms;
		ordTerms.length = numOrdTerms + 1;
		ordTerms[0] = res[0];
		debug(xpath)logline("res[0]="~tostring(res[0])~"\n");
		numOrdTerms = 0; // we're using this as current position, now
		foreach (i,pred;predlist) if (i%2) {
			if (pred == "and") {
				debug(xpath)logline("combining anded terms on ord term "~tostring(numOrdTerms)~" and i="~tostring(i)~" with res.length="~tostring(res.length)~" and attrlist.length="~tostring(predlist.length)~"\n");
				ordTerms[numOrdTerms] &= res[i+1];
				debug(xpath)logline("res["~tostring(i+1)~"]="~tostring(res[i+1])~"\n");
			} else if (pred == "or") {
				numOrdTerms++;
				ordTerms[numOrdTerms] = res[i+1];
			} else {
				throw new XPathError("Erm...nuh uh");
			}
		}
		// now that results have been determined, map them to a final result using "and" and "or"
		bool ret = false;
		foreach (val;ordTerms) ret |= val;
		debug(xpath)logline("Ended up with "~tostring(ret)~"\n");
		return ret;
	}

	private bool compareXPathPredicate(string elem1, string comparator, string elem2, string elem1value, bool caseSen) {
		// make sure that if we pulled a comparator, there's something to compare on the other side
		if (comparator.length && !elem2.length) throw new XPathError("Got a comparator without anything to compare");
		if (comparator.length) {
			bool lres,i1num = isNumeric(elem1value),i2num = isNumeric(elem2);
			if (comparator[0] == '<' || comparator[0] == '>') {
				// Must be numeric
				if (!i2num) {
					throw new XPathError("Badly formed XPath query: comparator '"~comparator~"' requires a numeric operand Not ("~elem2~")");
				}
				if (!i1num) {
					return false;
				}
			
				// get numeric equivalents
				double i1 = atof(elem1value);
				double i2 = atof(elem2);

				if (comparator[0] == '<') {
					lres = i1 < i2;
				} else /*if (comparator[0] == '>')*/ {
					lres = i1 > i2;
				}
				// check to see if equality is also called for
				if (comparator[$-1] == '=') {
					lres |= (i1 == i2);
				}
			} else {
				bool neg = false;
				if (comparator[0] == '!') neg = true;

				if (!i1num || !i2num) {
					if ((elem1value != elem2 && caseSen) || (elem1value.icmp(elem2) != 0 && !caseSen)) {
						debug(xpath)logline("search value "~elem2~" did not match attribute value "~elem1value~"\n");
						lres = false;
					} else {
						lres = true;
					}
				} else {
					// get numeric equivalents
					double i1 = atof(elem1value);
					double i2 = atof(elem2);
					lres = (i1 == i2);
				}
				if (neg) lres = !lres;
			}
			return lres;
		}
		return false;
	}

	private bool isDeepPath(string xpath) {
		// check to see if we're currently searching a deep path
		if (xpath.length > 1 && xpath[0] == '/' && xpath[1] == '/') {
			return true;
		}
		return false;
	}

	// this does not modify the incoming string, only pulls a slice out of it
	private string getNextNode(string xpath,out string truncxpath) {
		if (isDeepPath(xpath)) xpath = xpath[2..$];
		// dig through the pile of xpath, but make sure to respect attribute matches properly
		int contexts = 0;
		foreach (i,c;xpath) {
			if (c == '[') contexts++;
			if (c == ']') contexts--;
			if (c == '/' && !contexts) {
				// we've found the end of the current node
				truncxpath = xpath[i..$];
				return xpath[0..i];
			}
		}
		// i'm not sure this can occur unless the string was blank to begin with...
		truncxpath = null;
		return xpath;
	}

	/// Index override for getting attributes.
	string opIndex(string attr) {
		return getAttribute(attr);
	}

	/// Index override for getting children.
	DataSet opIndex(size_t childnum) {
		if (childnum < _children.length) return _children[childnum];
		return null;
	}

	/// Index override for setting attributes.
	DataSet opIndexAssign(string value,string name) {
		return setAttribute(name,value);
	}

	/// Index override for replacing children.
	DataSet opIndexAssign(DataSet x,int childnum) {
		if (childnum > _children.length) throw new Exception("Child element assignment is outside of array bounds");
		_children[childnum] = x;
		return this;
	}
}

/// A class specialization for CData nodes.
class CData : DataSet
{
	private string _cdata;

	/// Override the string constructor, assuming the data is coming from a user program, possibly with unescaped XML entities that need escaping.
	this(string cdata) {
		setCData(cdata);
	}

	this(){}

	/// Get CData string associated with this object.
	/// Returns: Parsed Character Data with decoded XML entities
	override string getCData() {
		return xmlDecode(_cdata);
	}

	/// This function assumes data is coming from user input, possibly with unescaped XML entities that need escaping.
	override CData setCData(string cdata) {
		_cdata = xmlEncode(cdata);
		return this;
	}

	/// This function resets the node to a default state
	override void reset() {
		// put back in the pool of available CData nodes if possible
		if (_docroot) {
			_docroot.cdataNodes.length = _docroot.cdataNodes.length + 1;
			_docroot.cdataNodes[$-1] = this;
		}
		_cdata = null;
	}

	/// This outputs escaped XML entities for use on the network or in a document.
	protected override string toString() {
		return _cdata;
	}

	/// Deprecated pretty writer
	deprecated protected override string write(string indent=null) {
		return toPrettyString(indent);
	}

	/// This outputs escaped XML entities for use on the network or in a document in pretty, tabbed format.
	protected override string toPrettyString(string indent=null) {
		return indent~toString()~"\n";
	}

	override string asCloseTag() { return null; }

	/// This throws an exception because CData nodes do not have names.
	override string getName() {
		throw new XmlError("CData nodes do not have names to get.");
	}

	/// This throws an exception because CData nodes do not have names.
	override void setName(string newName) {
		throw new XmlError("CData nodes do not have names to set.");
	}

	/// This throws an exception because CData nodes do not have attributes.
	override bool hasAttribute(string name) {
		throw new XmlError("CData nodes do not have attributes.");
	}

	/// This throws an exception because CData nodes do not have attributes.
	override string getAttribute(string name) {
		throw new XmlError("CData nodes do not have attributes to get.");
	}

	/// This throws an exception because CData nodes do not have attributes.
	override string[string] getAttributes() {
		throw new XmlError("CData nodes do not have attributes to get.");
	}

	/// This throws an exception because CData nodes do not have attributes.
	override DataSet setAttribute(string name, string value) {
		throw new XmlError("CData nodes do not have attributes to set.");
	}

	/// This throws an exception because CData nodes do not have attributes.
	override DataSet setAttribute(string name, long value) {
		throw new XmlError("CData nodes do not have attributes to set.");
	}

	/// This throws an exception because CData nodes do not have attributes.
	override DataSet setAttribute(string name, float value) {
		throw new XmlError("CData nodes do not have attributes to set.");
	}

	/// This throws an exception because CData nodes do not have children.
	override DataSet addChild(DataSet newNode) {
		throw new XmlError("Cannot add a child node to CData.");
	}

	/// This throws an exception because CData nodes do not have children.
	override DataSet addCData(string cdata) {
		throw new XmlError("Cannot add a child node to CData.");
	}
}

/// A specialization of CData for <![CDATA[]]> nodes
class UCData : CData {
	/// Get CData string associated with this object.
	/// Returns: Unparsed Character Data
	override string getCData() {
		return _cdata;
	}

	/// This function assumes data is coming from user input, possibly with unescaped XML entities that need escaping.
	override CData setCData(string cdata) {
		_cdata = cdata;
		return this;
	}

	/// This function resets the node to a default state
	override void reset() {
		// put back in the pool of available CData nodes if possible
		if (_docroot) {
			_docroot.ucdataNodes.length = _docroot.ucdataNodes.length + 1;
			_docroot.ucdataNodes[$-1] = this;
		}
		_cdata = null;
	}

	/// This outputs escaped XML entities for use on the network or in a document.
	protected override string toString() {
		return "<![CDATA["~_cdata~"]]>";
	}
}

/// A class specialization for XML instructions.
class XmlPI : DataSet {
	this(){}

	/// Override the constructor that takes a name so that it's accessible.
	this(string name) {
		super(name);
	}

	/// This node can't have children, and so can't have CData.
	/// Should this throw an exception?
	override string getCData() {
		return null;
	}

	/// Override toString for output to be used by parsers.
	override string toString() {
		return asOpenTag();
	}

	/// This function resets the node to a default state
	override void reset() {
		// put back in the pool of available CData nodes if possible
		_name = null;
		_attributes = null;
		if (_docroot) {
			_docroot.xmlPINodes.length = _docroot.xmlPINodes.length + 1;
			_docroot.xmlPINodes[$-1] = this;
		}
	}

	/// Deprecated pretty print to be used by parsers.
	deprecated protected override string write(string indent=null) {
		return toPrettyString(indent);
	}

	/// Pretty print to be used by parsers.
	protected override string toPrettyString(string indent=null) {
		return indent~asOpenTag()~"\n";
	}

	// internal function to generate opening tags
	override string asOpenTag() {
		if (_name.length == 0) {
			return null;
		}
		auto s = "<?" ~ _name ~ genAttrString() ~ "?>";
		return s;
	}

	// internal function to generate closing tags
	override string asCloseTag() { return null; }

	/// You can't add a child to something that can't have children.  There is no adoption in XML world.
	override DataSet addChild(DataSet newNode) {
		throw new XmlError("Cannot add a child node to XmlPI.");
	}

	/// You can't add a child to something that can't have children.  There is no adoption in XML world.
	/// Especially for red-headed stepchildren CData nodes.
	override DataSet addCData(string cdata) {
		throw new XmlError("Cannot add a child node to XmlPI.");
	}
}

/// A class specialization for XML comments.
class XmlComment : DataSet {
	string _comment;
	this(){}
	this(string comment) {
		_comment = comment;
		super(null);
	}

	/// This node can't have children, and so can't have CData.
	/// Should this throw an exception?
	override string getCData() {
		return null;
	}

	/// This function resets the node to a default state
	override void reset() {
		// put back in the pool of available XmlComment nodes if possible
		_comment = null;
		if (_docroot) {
			_docroot.xmlCommentNodes.length = _docroot.xmlCommentNodes.length + 1;
			_docroot.xmlCommentNodes[$-1] = this;
		}
	}

	/// Override toString for output to be used by parsers.
	override string toString() {
		return asOpenTag();
	}

	/// Deprecated pretty print to be used by parsers.
	deprecated protected override string write(string indent=null) {
		return toPrettyString(indent);
	}

	/// Pretty print to be used by parsers.
	protected override string toPrettyString(string indent=null) {
		return indent~asOpenTag()~"\n";
	}

	// internal function to generate opening tags
	protected override string asOpenTag() {
		if (_name.length == 0) {
			return null;
		}
		auto s = "<!--" ~ _comment  ~ "-->";
		return s;
	}

	// internal function to generate closing tags
	override string asCloseTag() { return null; }

	/// The members of Project Mayhem have no name... (this throws an exception)
	override string getName() {
		throw new XmlError("Comment nodes do not have names to get.");
	}

	/// Ditto. (this throws an exception)
	override void setName(string newName) {
		throw new XmlError("Comment nodes do not have names to set.");
	}

	/// These events can not be attributed to space monkeys. (this throws an exception)
	override bool hasAttribute(string name) {
		throw new XmlError("Comment nodes do not have attributes.");
	}

	/// Ditto. (this throws an exception)
	override string getAttribute(string name) {
		throw new XmlError("Comment nodes do not have attributes to get.");
	}

	/// Ditto. (this throws an exception)
	override string[string] getAttributes() {
		throw new XmlError("Comment nodes do not have attributes to get.");
	}

	/// Ditto. (this throws an exception)
	override DataSet setAttribute(string name, string value) {
		throw new XmlError("Comment nodes do not have attributes to set.");
	}

	/// Ditto. (this throws an exception)
	override DataSet setAttribute(string name, long value) {
		throw new XmlError("Comment nodes do not have attributes to set.");
	}

	/// Ditto. (this throws an exception)
	override DataSet setAttribute(string name, float value) {
		throw new XmlError("Comment nodes do not have attributes to set.");
	}

	/// Comments don't have children. (this throws an exception)
	override DataSet addChild(DataSet newNode) {
		throw new XmlError("Cannot add a child node to comment.");
	}

	/// Ditto. (this throws an exception)
	override DataSet addCData(string cdata) {
		throw new XmlError("Cannot add a child node to comment.");
	}
}

/** This is the encapsulating class for xml documents that allows reuse of nodes
  * so as to not allocate ALL THE TIME if you find it convenient to reuse the structure
  * Example:
  *--------------------------
  * string xmlstring = "<message responseID=\"1234abcd\" text=\"weather 12345\" type=\"message\"><flags>triggered</flags><flags>targeted</flags></message>";
  * // here we have the creation of an XmlDocument using the static opCall
  * auto newdoc = XmlDocument(xmlstring);
  * // reset rips apart the node tree to be reused
  * newdoc.reset;
  * // so reuse the XmlDocument that already has allocated nodes
  * newdoc.parse(xmlstring);
  * // here we have the creation of a secondary with a constructor
  * newdoc = new XmlDocument();
  * newdoc.parse(xmlstring);
  * // and again with the parse constructor
  * newdoc = new XmlDocument(xmlstring);
  * // XmlDocuments act like DataSet without attributes or names, so you can add children
  * newdoc.addCData("A long long time ago, in a galaxy far far away...");
  *--------------------------
  */
public int prealloc = 50;
class XmlDocument:DataSet {
	// this should inherit the reset and toString that we want
	protected DataSet[]xmlNodes;
	protected XmlComment[]xmlCommentNodes;
	protected CData[]cdataNodes;
	protected UCData[]ucdataNodes;
	protected XmlPI[]xmlPINodes;
	this() {
		_docroot = this;
		// allocate some DataSet to kick us off
		xmlNodes.length = prealloc;
		DataSet tmp;
		foreach(ref node;xmlNodes) {
			tmp = new DataSet();
			tmp._docroot = this;
			node = tmp;
		}
		super();
	}


	/// This static opCall should be used when creating new XmlDocuments for use
	static XmlDocument opCall(string constring,bool preserveWS = false) {
		auto root = new XmlDocument;
		root.parse(constring,preserveWS);
		return root;
	}

	/// This function resets the node to a default state
	override void reset() {
		foreach(child;_children) {
			child.reset;
		}
		_children.length = 0;
	}

	void parse(string constring,bool preserveWS = false) {
		string pointcpy = constring;
		try {
			addChildren(constring,preserveWS);
		} catch (XmlError e) {
			logline("Caught exception from input string:\n"~pointcpy~"\n");
			throw e;
		}
	}

	/// Allow usage of the free list and allocation for DataSet if necessary.
	DataSet allocDataSet() {
		DataSet tmp;
		// use already allocated instances if available
		if (xmlNodes.length) {
			tmp = xmlNodes[$-1];
			xmlNodes.length = xmlNodes.length - 1;
		} else {
			// otherwise, allocate a new one and set it up properly
			tmp = new DataSet();
			tmp._docroot = this;
		}
		return tmp;
	}

	/// Allow usage of the free list and allocation for CData nodes if necessary.
	CData allocCData() {
		CData tmp;
		// use already allocated instances if available
		if (cdataNodes.length) {
			tmp = cdataNodes[$-1];
			cdataNodes.length = cdataNodes.length - 1;
		} else {
			// otherwise, allocate a new one and set it up properly
			tmp = new CData();
			tmp._docroot = this;
		}
		return tmp;
	}

	/// Allow usage of the free list and allocation for UCData nodes if necessary.
	UCData allocUCData() {
		UCData tmp;
		// use already allocated instances if available
		if (ucdataNodes.length) {
			tmp = ucdataNodes[$-1];
			ucdataNodes.length = ucdataNodes.length - 1;
		} else {
			// otherwise, allocate a new one and set it up properly
			tmp = new UCData();
			tmp._docroot = this;
		}
		return tmp;
	}

	/// Allow usage of the free list and allocation for XmlComments if necessary.
	XmlComment allocXmlComment() {
		XmlComment tmp;
		// use already allocated instances if available
		if (xmlCommentNodes.length) {
			tmp = xmlCommentNodes[$-1];
			xmlCommentNodes.length = xmlCommentNodes.length - 1;
		} else {
			// otherwise, allocate a new one and set it up properly
			tmp = new XmlComment();
			tmp._docroot = this;
		}
		return tmp;
	}

	/// Allow usage of the free list and allocation for XmlPIs if necessary.
	XmlPI allocXmlPI() {
		XmlPI tmp;
		// use already allocated instances if available
		if (xmlPINodes.length) {
			tmp = xmlPINodes[$-1];
			xmlPINodes.length = xmlPINodes.length - 1;
		} else {
			// otherwise, allocate a new one and set it up properly
			tmp = new XmlPI();
			tmp._docroot = this;
		}
		return tmp;
	}
}


/// Encode characters such as &, <, >, etc. as their xml/html equivalents
string xmlEncode(string src) {
	src = replace(src, "&", "&amp;");
	src = replace(src, "<", "&lt;");
	src = replace(src, ">", "&gt;");
	src = replace(src, "\"", "&quot;");
	src = replace(src, "'", "&apos;");
	return src;
}

/// Convert xml-encoded special characters such as &amp;amp; back to &amp;.
string xmlDecode(string src) {
	src = replace(src    , "&lt;",  "<");
	src = replace(src, "&gt;",  ">");
	src = replace(src, "&apos;", "'");
	src = replace(src, "&quot;",  "\"");
	// take care of decimal character entities
	src = regrep(src,"&#\\d{1,8};",(string m) {
		auto cnum = m[2..$-1];
		dchar dnum = cast(dchar)atoi(cnum);
		return quickUTF8(dnum);
	});
	// take care of hex character entities
	src = regrep(src,"&#[xX][0-9a-fA-F]{1,8};",(string m) {
		auto cnum = m[3..$-1];
		dchar dnum = hex2dchar(cnum);
		return quickUTF8(dnum);
	});
	src = replace(src, "&amp;", "&");
	return src;
}

// a quick dchar to utf8 conversion
private string quickUTF8(dchar dachar) {
	char[]ret;
	foreach(char r;[dachar]) {
		ret ~= r;
	}
	return cast(string)ret;
}

// convert a hex string to a raw dchar
private dchar hex2dchar (string hex) {
	dchar res = 0;
	foreach(digit;hex) {
		res <<= 4;
		res |= toHVal(digit);
	}
	return res;
}

// convert a single hex digit to its raw value
private dchar toHVal(char digit) {
	if (digit >= '0' && digit <= '9') {
		return digit-'0';
	}
	if (digit >= 'a' && digit <= 'f') {
		return digit-'a'+10;
	}
	if (digit >= 'A' && digit <= 'F') {
		return digit-'A'+10;
	}
	return 0;
}

unittest {
	string xmlstring = "<message responseID=\"1234abcd\" text=\"weather 12345\" type=\"message\" order=\"5\"><flags>triggered</flags><flags>targeted</flags></message>";
	DataSet xml = xmlstring.readDocument();
	xmlstring = xml.toString;
	// ensure that the string doesn't mutate after a second reading, it shouldn't
	logline("kxml.xml test\n");
	assert(xmlstring.readDocument().toString == xmlstring);
	logline("kxml.xml XPath test\n");
	DataSet[]searchlist = xml.parseXPath("message/flags");
	assert(searchlist.length == 2 && searchlist[0].getName == "flags");

	logline("kxml.xml deep XPath test\n");
	searchlist = xml.parseXPath("//message//flags");
	assert(searchlist.length == 2 && searchlist[0].getName == "flags");

	logline("kxml.xml attribute match 'and' XPath test\n");
	searchlist = xml.parseXPath("/message[@type=\"message\" and @responseID=\"1234abcd\"]/flags");
	assert(searchlist.length == 2 && searchlist[0].getName == "flags");
	searchlist = xml.parseXPath("message[@type=\"toaster\"]/flags");
	assert(searchlist.length == 0);

	logline("kxml.xml attribute match 'or' XPath test\n");
	searchlist = xml.parseXPath("/message[@type=\"message\" or @responseID=\"134abcd\"]/flags");
	assert(searchlist.length == 2 && searchlist[0].getName == "flags");
	searchlist = xml.parseXPath("/message[@type=\"yarblemessage\" or @responseID=\"1234abcd\"]/flags");
	assert(searchlist.length == 2 && searchlist[0].getName == "flags");

	logline("kxml.xml XPath inequality test\n");
	searchlist = xml.parseXPath("/message[@order<6]/flags");
	assert(searchlist.length == 2 && searchlist[0].getName == "flags");
	searchlist = xml.parseXPath("/message[@order>4]/flags");
	assert(searchlist.length == 2 && searchlist[0].getName == "flags");
	searchlist = xml.parseXPath("/message[@order>=5]/flags");
	assert(searchlist.length == 2 && searchlist[0].getName == "flags");
	searchlist = xml.parseXPath("/message[@order<=5]/flags");
	assert(searchlist.length == 2 && searchlist[0].getName == "flags");
	searchlist = xml.parseXPath("/message[@order!=1]/flags");
	assert(searchlist.length == 2 && searchlist[0].getName == "flags");
	searchlist = xml.parseXPath("/message[@order=5]/flags");
	assert(searchlist.length == 2 && searchlist[0].getName == "flags");

	/*logline("kxml.xml XPath subnode match test\n");
	searchlist = xml.parseXPath("/message[flags@tweak]");
	assert(searchlist.length == 2 && searchlist[0].getName == "flags");*/

	logline("kxml.xml XPath ??? tests\n");
	searchlist = xml.parseXPath(`//@text`);
	assert(searchlist.length == 1 && searchlist[0].getCData == "weather 12345");
	searchlist = xml.parseXPath(`/message[flags="triggered" and flags="targeted"]/@order`);
	assert(searchlist.length == 1 && searchlist[0].getCData == "5");
	searchlist = xml.parseXPath(`/message[@order<6 and flags="triggered"]/flags`);
	assert(searchlist.length == 2 && searchlist[0].getName == "flags");
	searchlist = xml.parseXPath(`/message[@order<6 and flags="fail"]/flags`);
	assert(searchlist.length == 0);

	xmlstring = "<![CDATA[cdata test <>>>>]]>";
	xml = xmlstring.readDocument();
	assert(xml.getCData == "cdata test <>>>>");
	assert(xml.toString() == "<![CDATA[cdata test <>>>>]]>");

	xmlstring =
	`<table class="table1">
	<tr>	 <th>URL </th><td><a href="path1/path2">Link 1.1</a></td></tr>
	<tr ab="two"><th>Head</th><td>Text 1.2</td></tr>
	<tr ab="4">  <th>Head</th><td>Text 1.3</td></tr>
	</table>
	<table class="table2">
	<tr>	 <th>URL </th><td><a href="path1/path2">Link 2.1</a></td></tr>
	<tr ab="six"><th>Head</th><td>Text 2.2</td></tr>
	<tr ab="9">  <th>Head</th><td>Text 2.3</td></tr>
	</table>`;

	logline("Running More tests\n");
	xml = readDocument(xmlstring);

	logline("kxml.xml XPath no-match tests\n");
	searchlist = xml.parseXPath(`//ab`);
	assert(searchlist.length == 0);
	searchlist = xml.parseXPath(`//ab=9`);		// Should this throw?
	assert(searchlist.length == 0);
	searchlist = xml.parseXPath(`//td="Text2.2"`);	// Should this throw?
	assert(searchlist.length == 0);
	searchlist = xml.parseXPath(`//tr[ab<=7]/td`);
	assert(searchlist.length == 0);

	logline("kxml.xml XPath attr tests\n");
	searchlist = xml.parseXPath(`//@ab`);
	assert(searchlist.length == 4);
	searchlist = xml.parseXPath(`//@ab<=7`);
	assert(searchlist.length == 1);
	searchlist = xml.parseXPath(`//table[@class!="table2"]//@ab`);
	assert(searchlist.length == 2);
//	searchlist = xml.parseXPath(`//@class!="table2"//@ab`);	// Should this work?
//	assert(searchlist.length == 2);

	logline("kxml.xml XPath predicate tests\n");
	searchlist = xml.parseXPath(`//tr[@ab<=7]/td`);
	assert(searchlist.length == 1 && searchlist[0].getCData == "Text 1.3");
	searchlist = xml.parseXPath(`//tr[@ab>=9 and th="Head"]/td`);
	assert(searchlist.length == 1 && searchlist[0].getCData == "Text 2.3");

	logline("kxml.xml XPath cdata matching tests\n");
	searchlist = xml.parseXPath(`//td[.="Text 2.3"]`);
	assert(searchlist.length == 1);

}

version(XML_main) {
	void main(){}
}

