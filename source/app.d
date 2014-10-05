import vibe.d;
import kxml.xml;
import mysql.connection;
import std.stdio;
import mysql.db;
import std.conv;
import onyx.config.bundle;
import std.variant;

MysqlDB mdb;
string db_version;
string[] curTables;
MetaData md;
bool refresh_db = true;

string getDSN() {
  auto bundle = immutable ConfBundle("conf/example.conf");
  auto host = bundle.value("database", "host");
  auto port = bundle.value("database", "port");
  auto user = bundle.value("database", "user");
  auto pwd = bundle.value("database", "pwd");
  auto db = bundle.value("database", "db");
  db_version = bundle.value("database", "db_version");
  return("host=" ~ host ~ ";port=" ~ port ~ ";user=" ~ user ~ ";pwd=" ~ pwd ~ ";db=" ~ db);
}

Connection getDBConnection() {
  Connection c;

  try {
    if (refresh_db) {
      mdb = new MysqlDB(getDSN());
    }

    c = mdb.lockConnection();

    if (refresh_db) {
      md = MetaData(c);
      curTables = md.tables();
      refresh_db = false;
    }
  } catch (Exception e1) {
    // Now what, though. How do we inform the client?
    logError("Exception: " ~ e1.msg);
  }

  return(c);
}

shared static this() {
	auto settings = new HTTPServerSettings;
	settings.port = 8181;
	settings.bindAddresses = ["::1", "127.0.0.1"];

  auto router = new URLRouter;
  // Get a list of the available tables
  router.get("/tables/list", &getTableList);
  router.get("/tables/list/:format", &getTableList);

  // Get all the rows of a specific table
  router.get("/table/:tableName", &getTable);
  router.get("/table/:tableName/:format", &getTable);

  // Get a list of the columns in a table
  router.get("/columns/:tableName", &getColumnList);
  router.get("/columns/:tableName/:format", &getColumnList);

  // Lookup by ID and return Name
  router.get("/item/lookup/Name/:itemID", &lookupItem);
  router.get("/item/lookup/Name/:itemID/:format", &lookupItem);

  // Lookup by Name and return ID
  router.get("/item/lookup/ID/:itemName", &lookupItem);
  router.get("/item/lookup/ID/:itemName/:format", &lookupItem);

	listenHTTP(settings, router);

	logInfo("Please open http://127.0.0.1:8181/ in your browser.");
}

XmlNode createRootElement() {
  return(new XmlNode("eve_static").setAttribute("db_version", db_version).setAttribute("error", false));
}

string getFormat(HTTPServerRequest req) {
  string valid_formats[] = ["text", "xml"];

  try {
    foreach(fmt; valid_formats) {
      string format = req.params["format"];
      if (fmt == format) {
        return(format);
      }
    }
  } catch (RangeError) {
    // Fallthrough to XML
  }
  return("xml");
}

string getErrorResponse(string msg, string format) {
  refresh_db = true;

  // Replace this with a case statement
  switch (format) {
    case "xml":
    default:
      // XML is the default
      XmlNode root = createRootElement();
      root.setAttribute("error", true);
      root.addChild(new XmlNode("error").addCData(msg));
      logError("Exception: " ~ msg);
      return(root.toPrettyString);

    case "text":
      return("ERROR: " ~ msg);
  }
}

void getTableList(HTTPServerRequest req, HTTPServerResponse res) {
  XmlNode root = createRootElement();
  Connection c;

  try {
    c = getDBConnection();
    scope(exit) c.close();

    switch (getFormat(req)) {
      case "xml":
      default:
        XmlNode tables = new XmlNode("tables");
        foreach(tbls; curTables) {
          tables.addChild(new XmlNode(tbls));
        }
        root.addChild(tables);
	      res.writeBody(root.toPrettyString);
        break;

      case "text":
        string output;
        foreach(tbls; curTables) {
          output ~= tbls ~ "\n";
        }
        res.writeBody(output);
        break;
    }
  } catch (Exception e1) {
    res.writeBody(getErrorResponse(e1.msg, getFormat(req)));
  }
}

void getColumnList(HTTPServerRequest req, HTTPServerResponse res) {
  string table = req.params["tableName"];
  XmlNode root = createRootElement();

  try {
    // This isn't really needed for any other reason than to jog the DB connection if needed.
    getDBConnection();
    auto curColumns = md.columns(table);

    switch (getFormat(req)) {
      case "xml":
      default:
        XmlNode columns = new XmlNode("columns").setAttribute("table", table);
        foreach(cols; curColumns) {
          columns.addChild(new XmlNode(cols.name));
        }
        root.addChild(columns);
	      res.writeBody(root.toPrettyString);
        break;

      case "text":
        string output;
        foreach(cols; curColumns) {
          output ~= cols.name ~ "\n";
        }
        res.writeBody(output);
        break;
    }
  } catch (Exception e1) {
    res.writeBody(getErrorResponse(e1.msg, getFormat(req)));
  }
}

bool stringInArray(string str, string[] arr) {
  foreach (tstr; arr) {
    if (str == tstr) {
      return(true);
    }
  }
  return(false);
}

bool colInCurColumns(string col, ColumnInfo[] curColumns) {
  foreach (ccol; curColumns) {
    if (col == ccol.name) {
      return(true);
    }
  }
  return(false);
}

string generateSQLParams(ulong count) {
  string params;

  for (ulong i = 0; i < count; i++) {
    if (params) {
      params ~= ", ?";
    } else {
      params = "?";
    }
  }
  return(params);
}

void getTable(HTTPServerRequest req, HTTPServerResponse res) {
  auto col_filter_r = req.query.get("cols");
  auto match_col = req.query.get("match_col");
  auto match_filter_r = req.query.get("match_filter");
  auto match_filter = split(match_filter_r, ",");

  string table = req.params["tableName"];
  bool table_found = false;
  Connection c;
  XmlNode root = createRootElement();

  try {
    c = getDBConnection();
    scope(exit) c.close();

    foreach(tbls ; curTables) {
      if (table == tbls) {
        table_found = true;
      }
    }
  } catch (Exception e1) {
    res.writeBody(getErrorResponse(e1.msg, getFormat(req)));
    return;
  }

  if (!table_found) {
    res.writeBody(getErrorResponse("No such table: " ~ table, getFormat(req)));
    return;
  }

  ResultSet results;
  ColumnInfo[] curColumns;
  try {
    curColumns = md.columns(table);
    //pragma(msg, typeof(curColumns))
    auto command = new Command(c);

    auto col_filter_a = split(col_filter_r, ",");
    string col_filter;
    if (col_filter_r) {
      foreach (f; col_filter_a) {
        if (colInCurColumns(f, curColumns)) {
          if (col_filter) {
            col_filter ~= ", " ~ f;
          } else {
            col_filter = f;
          }
        }
      }
    } else {
      col_filter = "*";
    }

    // Make sure match_col exists
    if (!colInCurColumns(match_col, curColumns)) {
      res.writeBody(getErrorResponse("Not a valid columns: " ~ match_col , getFormat(req)));
    }

    if (match_col) {
      command.sql = "SELECT " ~ col_filter ~ " FROM " ~ table ~ " WHERE " ~ match_col ~ " IN (" ~ generateSQLParams(match_filter.length) ~ ")";
    } else {
      command.sql = "SELECT " ~ col_filter ~ " FROM " ~ table;
    }
    command.prepare;
    Variant[] va;
    va.length = match_filter.length;
    for (int i = 0; i < match_filter.length; i++) {
      va[i] = match_filter[i];
    }
    command.bindParameters(va);
    results = command.execPreparedResult();
  } catch (AssertError e1) {
    res.writeBody(getErrorResponse(e1.msg ~ ": This is a known error with native-mysql. Waiting for it to be fixed.", getFormat(req)));
    return;
  } catch (Exception e1) {
    res.writeBody(getErrorResponse(e1.msg, getFormat(req)));
    return;
  }

  XmlNode node = new XmlNode(table).setAttribute("rowsReturned", results.length);

  foreach (row; results) {
    XmlNode row_xml = new XmlNode("row");

    foreach (foo; results.colNames) {
      row_xml.addChild(new XmlNode(foo).addCData(row[results.colNameIndicies[foo]].to!string()));
    }

    node.addChild(row_xml);
  }

  root.addChild(node);
  switch (getFormat(req)) {
    case "xml":
    default:
	    res.writeBody(root.toPrettyString);
      break;

    case "text":
      res.writeBody("ERROR: getTable doesn't currently support 'text' as an output format");
      break;
  }
}

void lookupItem(HTTPServerRequest req, HTTPServerResponse res) {
  enum { ID, NAME }
  int action, itemID;
  string output, itemName;
  string node_name, node_attr, node_attr_val;
  Connection c;
  XmlNode root = createRootElement;

  try {
    c = getDBConnection();
    scope(exit) c.close();
  } catch (Exception e1) {
    res.writeBody(getErrorResponse(e1.msg, getFormat(req)));
    return;
  }

  ResultSet results;
  try {
    itemID = req.params["itemID"].to!int;
    action = ID;
  } catch (RangeError) {
    // ignoring
  }
  try {
    itemName = req.params["itemName"];
    action = NAME;
  } catch (RangeError) {
    // ignoring
  }

  auto command = new Command(c);
  switch (action) {
    case ID:
      command.sql = "SELECT itemName FROM invNames WHERE itemID = ?";
      command.prepare();
      command.bindParameter(itemID, 0);
      results = command.execPreparedResult();
      output = results[0][0].get!string;
      node_name = "itemName";
      node_attr = "id";
      node_attr_val = itemID.to!string;
      break;

    case NAME:
      command.sql = "SELECT itemID FROM invNames WHERE itemName = ?";
      command.prepare();
      command.bindParameter(itemName, 0);
      results = command.execPreparedResult();
      output = results[0][0].to!string;
      node_name = "itemID";
      node_attr = "name";
      node_attr_val = itemName;
      break;

    default:
      res.writeBody(getErrorResponse("This REALLY shouldn't happen, but action is: " ~ action.to!string, getFormat(req)));
      return;
  }

  switch (getFormat(req)) {
    case "xml":
    default:
      root.addChild(new XmlNode(node_name).setAttribute(node_attr, node_attr_val).setCData(output));
      res.writeBody(root.toPrettyString);
      break;

    case "text":
      res.writeBody(output);
      break;
  }
}
