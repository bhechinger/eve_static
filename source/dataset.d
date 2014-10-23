import vibe.textfilter.html;
import vibe.data.json;
import kxml.xml;
//import std.stdio;
import std.conv;

class DataSetError : Exception {
  this(string msg) {
    super(msg);
  }
}

class DataSet {
	protected string _name;
	protected string[string] _attributes;
	protected DataSet[]      _children;

  string valid_formats[] = ["text", "xml", "exml"];

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
			return _attributes[name];
		else
			return null;
	}

	/// Return an array of all attributes
	string[string] getAttributes() {
		string[string]tmp;
		foreach(key; _attributes.keys) {
			tmp[key] = _attributes[key];
		}
		return tmp;
	}

	/// Set an attribute to a string value.
	/// The attribute is created if it doesn't exist.
	DataSet setAttribute(string name, string value) {
		_attributes[name] = value;
		return this;
	}

	/// Set an attribute to an integer value (stored internally as a string).
	/// The attribute is created if it doesn't exist.
	DataSet setAttribute(string name, long value) {
		return setAttribute(name, value.to!string);
	}

	/// Set an attribute to a float value (stored internally as a string).
	/// The attribute is created if it doesn't exist.
	DataSet setAttribute(string name, float value) {
		return setAttribute(name, value.to!string);
	}

	/// Remove the attribute with name.
	DataSet removeAttribute(string name) {
		_attributes.remove(name);
		return this;
	}

	/// Add a child node.
	DataSet addChild(DataSet newNode) {
		// let's bump things by increments of 10 to make them more efficient
		if (_children.length + 1 % 10 == 0) {
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
		for (size_t i = 0; i < _children.length; i++) {
      if (_children[i] is remove) {
			  // we matched it, so remove it
			  // don't return true yet, since we're removing all references to it, not just the first one
			  _children = _children[0..i]~_children[i+1..$];
      }
		}
		return len - _children.length;
	}

	/// Add a child Node of data (text).
	DataSet addData(string data) {
    auto d = new Data;
    d.setData(data);
		addChild(d);
		return this;
	}

	/// Check to see if this node is a Data node.
	final bool isData() {
		if (cast(Data)this) return true;
		return false;
	}

	/// This function makes life easier for those looking to pull data from a tag, in the case of multiple nodes, it pulls all first level data nodes.
	string getData() {
		string tmp;
		foreach(child; _children) {
      if (child.isData) {
			  tmp ~= child.getData(); 
      }
		}
		return tmp;
	}

	/// This function resets the node to a default state
	void reset() {
		foreach(child; _children) {
			child.reset;
		}
		_children.length = 0;
		_attributes = null;
		_name = null;
	}

	/// This function removes all child nodes from the current node
	DataSet removeChildren() {
		_children.length = 0;
		return this;
	}

  // TODO: This needs review
	/// This function sets the data inside the current node as intelligently as possible (without allocation, hopefully)
	DataSet setData(string data) {
		if (_children.length == 1 && _children[0].isData) {
			// since the only node is Data, just set the text and be done
			_children[0].setData(data);
		} else {
			removeChildren;
			addData(data);
		}
		return this;
	}

	// internal function used to generate the attribute list
	protected string genAttrString() {
		string ret;
		foreach (keys, values; _attributes) {
				ret ~= " " ~ keys ~ "=\"" ~ values ~ "\"";
		}
		return ret;
	}

	final protected bool isLeaf() {
		return _children.length == 0;
	}

  string getPrettyOutput(string format) {
    return getOutput(format, true);
  }

  string getOutput(string format, bool pretty = false) {
    if (format !in this.valid_formats) {
      return("ERROR: Unknown format: " ~ format);
    }

    switch (format) {
      case "xml":
      default:
        if (pretty) {
          return(this.toPrettyXML());
        } else {
          return(this.toXML());
        }

      case "exml":
        if (pretty) {
          return(htmlEscape(this.toPrettyXML()));
        } else {
          return(htmlEscape(this.toXML()));
        }

      case "json":
        if (pretty) {
          return(this.toPrettyJson());
        } else {
          return(this.toJson());
        }

      case "text":
        return(this.toText());
    }
  }

	override string toString() {
    return(generateJson().toString());
  }
  alias toString toJson;

	string toPrettyString() {
    return(generateJson().toPrettyString());
  }
  alias toPrettyString toPrettyJson;

  string toXML() {
    return(generateXML().toString());
  }

  string toPrettyXML() {
    return(generateXML().toPrettyString());
  }

  string toText() {
    return(generateText());
  }

	Json generateJson() {
    Json j;
    j = Json.emptyObject;
    if (_name) {
      j.name = _name;
    }

    if (_attributes) {
      j.attributes = Json.emptyObject;
      foreach (attr, value; _attributes) {
        j.attributes[attr] = value;
      }
    }

    if (this.isData()) {
      j.data = this.getData();
    }

		if (_children.length) {
      j.children = Json.emptyArray;
      foreach (child; _children) {
			  j.children ~= child.generateJson();
      }
		}

		return j;
	}

  XmlNode generateXML() {
    XmlNode x = new XmlNode(_name);

    if (_attributes) {
      foreach (attr, value; _attributes) {
        x.setAttribute(attr, value);
      }
    }

    if (this.isData()) {
      x.addCData(this.getData());
    }

		if (_children.length) {
      foreach (child; _children) {
			  x.addChild(child.generateXML());
      }
		}

		return x;
  }

  string generateText() {
    string t;

    if(_name) {
      t ~= _name;
    }

    if (_attributes) {
      foreach (attr, value; _attributes) {
        t ~= " - " ~ attr ~ ": " ~ value;
      }
    }

    if (this.isData()) {
      t ~= "  " ~ this.getData();
    }

		if (_children.length) {
      foreach (child; _children) {
        t ~= "\n" ~ child.generateText();
      }
		}

		return t;
  }

	/// Add array of nodes directly into this node as children.
	void addChildren(DataSet[] newChildren) {
		// let's bump things by increments of 10 to make them more efficient
		if (_children.length + newChildren.length % 10 < newChildren.length) {
			_children.length = _children.length + 10;
			_children.length = _children.length - 10;
		}
		_children.length = _children.length + newChildren.length;
		_children[$-newChildren.length..$] = newChildren[0..$];
	}

	/// Index override for getting attributes.
	string opIndex(string attr) {
		return getAttribute(attr);
	}

	/// Index override for getting children.
	DataSet opIndex(size_t childnum) {
		if (childnum < _children.length) {
      return _children[childnum];
    }
		return null;
	}

	/// Index override for setting attributes.
	DataSet opIndexAssign(string value, string name) {
		return setAttribute(name, value);
	}

	/// Index override for replacing children.
	DataSet opIndexAssign(DataSet x, int childnum) {
		if (childnum > _children.length) {
      throw new Exception("Child element assignment is outside of array bounds");
    }
		_children[childnum] = x;
		return this;
	}
}

/// A class specialization for Data nodes.
class Data : DataSet
{
	private string _data;

	/// Override the string constructor, assuming the data is coming from a user program, possibly with unescaped XML entities that need escaping.
	this(string data) {
		setData(data);
	}

	this(){}

	/// Get Data string associated with this object.
	/// Returns: Parsed Character Data with decoded XML entities
	override string getData() {
		return _data;
	}

	/// This function assumes data is coming from user input, possibly with unescaped XML entities that need escaping.
	override Data setData(string data) {
		_data = data;
		return this;
	}

	/// This function resets the node to a default state
	override void reset() {
		// put back in the pool of available Data nodes if possible
		_data = null;
	}

	/// This outputs escaped XML entities for use on the network or in a document.
	protected override string toString() {
		return _data;
	}

	/// This throws an exception because Data nodes do not have names.
	override string getName() {
		throw new DataSetError("Data nodes do not have names to get.");
	}

	/// This throws an exception because Data nodes do not have names.
	override void setName(string newName) {
		throw new DataSetError("Data nodes do not have names to set.");
	}

	/// This throws an exception because Data nodes do not have attributes.
	override bool hasAttribute(string name) {
		throw new DataSetError("Data nodes do not have attributes.");
	}

	/// This throws an exception because Data nodes do not have attributes.
	override string getAttribute(string name) {
		throw new DataSetError("Data nodes do not have attributes to get.");
	}

	/// This throws an exception because Data nodes do not have attributes.
	override string[string] getAttributes() {
		throw new DataSetError("Data nodes do not have attributes to get.");
	}

	/// This throws an exception because Data nodes do not have attributes.
	override DataSet setAttribute(string name, string value) {
		throw new DataSetError("Data nodes do not have attributes to set.");
	}

	/// This throws an exception because Data nodes do not have attributes.
	override DataSet setAttribute(string name, long value) {
		throw new DataSetError("Data nodes do not have attributes to set.");
	}

	/// This throws an exception because Data nodes do not have attributes.
	override DataSet setAttribute(string name, float value) {
		throw new DataSetError("Data nodes do not have attributes to set.");
	}

	/// This throws an exception because Data nodes do not have children.
	override DataSet addChild(DataSet newNode) {
		throw new DataSetError("Cannot add a child node to Data.");
	}

	/// This throws an exception because Data nodes do not have children.
	override DataSet addData(string data) {
		throw new DataSetError("Cannot add a child node to Data.");
	}
}

/* TODO: Find out how this works, this is snazzy looking
version(XML_main) {
	void main(){}
}
*/
