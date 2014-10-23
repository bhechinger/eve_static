import vibe.d;
import kxml.xml;
import mysql.connection;
import std.stdio;
import mysql.db;
import std.conv;
import onyx.config.bundle;
import std.variant;
import memcached4d;
import dataset;

enum { ID, NAME }
MysqlDB mdb;
string db_version;
string[] curTables;
MetaData md;
bool refresh_db = true;
MemcachedClient cache;

string getDSN() {
  auto bundle = immutable ConfBundle("conf/eve_static.conf");
  // TODO: Config file stuff all needs to be looked at. This is just here for temporary.
  cache = memcachedConnect(bundle.value("memcached", "servers"));
  auto host = bundle.value("database", "host");
  auto port = bundle.value("database", "port");
  auto user = bundle.value("database", "user");
  auto pwd = bundle.value("database", "pwd");
  auto db = bundle.value("database", "db");
  db_version = bundle.value("database", "db_version");
  return "host=" ~ host ~ ";port=" ~ port ~ ";user=" ~ user ~ ";pwd=" ~ pwd ~ ";db=" ~ db;
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

  return c;
}

shared static this() {
	auto settings = new HTTPServerSettings;
  auto bundle = immutable ConfBundle("conf/eve_static.conf");
	settings.port = 8181;
	settings.bindAddresses = [bundle.value("network", "listen")];

  auto router = new URLRouter;
  // Some trivial API documentation
  router.get("/help", &printHelp);

  // Get a list of the available tables
  router.get("/tables/list", &getTableListHandler);
  router.get("/tables/list/:format", &getTableListHandler);

  // Get all the rows of a specific table
  router.get("/table/:tableName", &getTableHandler);
  router.get("/table/:tableName/:format", &getTableHandler);

  // Get a list of the columns in a table
  router.get("/columns/:tableName", &getColumnListHandler);
  router.get("/columns/:tableName/:format", &getColumnListHandler);

  // Lookup by ID and return Name
  router.get("/lookup/:item/byID/:itemID", &lookupItemHandler);
  router.get("/lookup/:item/byID/:itemID/:format", &lookupItemHandler);

  // Lookup by Name and return ID
  router.get("/lookup/:item/byName/:itemName", &lookupItemHandler);
  router.get("/lookup/:item/byName/:itemName/:format", &lookupItemHandler);

  router.get("/get/blueprint/materials/:direction/:blueprint", &getBlueprintMatsHandler);
  router.get("/get/blueprint/materials/:direction/:blueprint/:format", &getBlueprintMatsHandler);
	listenHTTP(settings, router);

	logInfo("Please open http://127.0.0.1:8181/ in your browser.");
}

DataSet createRootElement() {
  return new DataSet("eve_static").setAttribute("db_version", db_version).setAttribute("error", false);
}

string getFormat(HTTPServerRequest req) {
  string valid_formats[] = ["text", "xml", "exml"];

  try {
    foreach(fmt; valid_formats) {
      string format = req.params["format"];
      if (fmt == format.toLower()) {
        return format;
      }
    }
  } catch (RangeError) {
    // Fallthrough to XML
  }
  return "xml";
}

string getErrorResponse(string msg, string format) {
  refresh_db = true;

  DataSet root = createRootElement();
  root.setAttribute("error", true);
  root.addChild(new DataSet("error").addData(msg));
  logError("Exception: " ~ msg);

  return root.getPrettyOutput(format);
}

void printHelp(HTTPServerRequest req, HTTPServerResponse res) {
  res.render!("index.dt", req);
}

void getTableListHandler(HTTPServerRequest req, HTTPServerResponse res) {
  res.writeBody(getTableList(getFormat(req)));
}

string getTableList(string format) {
  DataSet root = createRootElement();
  Connection c;

  try {
    c = getDBConnection();
    scope(exit) c.close();

    DataSet tables = new DataSet("tables");
    foreach(tbls; curTables) {
      tables.addChild(new DataSet(tbls));
    }
    root.addChild(tables);
    return root.getPrettyOutput(format);

  } catch (Exception e1) {
    return getErrorResponse(e1.msg, format);
  }
}

void getColumnListHandler(HTTPServerRequest req, HTTPServerResponse res) {
  res.writeBody(getColumnList(getFormat(req), req.params["tableName"]));
}

string getColumnList(string format, string table) {
  DataSet root = createRootElement();

  try {
    // This isn't really needed for any other reason than to jog the DB connection if needed.
    getDBConnection();
    auto curColumns = md.columns(table);

    DataSet columns = new DataSet("columns").setAttribute("table", table);
    foreach(cols; curColumns) {
      columns.addChild(new DataSet(cols.name));
    }
    root.addChild(columns);
    return root.getPrettyOutput(format);

  } catch (Exception e1) {
    return getErrorResponse(e1.msg, format);
  }
}

bool stringInArray(string str, string[] arr) {
  foreach (tstr; arr) {
    if (str == tstr) {
      return true;
    }
  }
  return false;
}

bool colInCurColumns(string col, ColumnInfo[] curColumns) {
  foreach (ccol; curColumns) {
    if (col == ccol.name) {
      return true;
    }
  }
  return false;
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
  return params;
}

void getTableHandler(HTTPServerRequest req, HTTPServerResponse res) {
  res.writeBody(getTable(getFormat(req), req.query.get("cols"), req.query.get("match_col"), req.query.get("match_filter"), req.params["tableName"]));
}

string getTable(string format, string col_filter_r, string match_col, string match_filter_r, string table) {
  auto match_filter = split(match_filter_r, ",");
  bool table_found = false;
  Connection c;
  DataSet root = createRootElement();

  try {
    c = getDBConnection();
    scope(exit) c.close();

    foreach(tbls ; curTables) {
      if (table == tbls) {
        table_found = true;
      }
    }
  } catch (Exception e1) {
    return getErrorResponse(e1.msg, format);
  }

  if (!table_found) {
    return getErrorResponse("No such table: " ~ table, format);
  }

  ResultSet results;
  ColumnInfo[] curColumns;
  try {
    curColumns = md.columns(table);
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
    //if (!colInCurColumns(match_col, curColumns)) {
     // res.writeBody(getErrorResponse("Not a valid columns: " ~ match_col , getFormat(req)));
    //}

    string memCacheKey;
    if (match_col) {
      memCacheKey = col_filter ~ "::" ~ table ~ "::" ~ match_col;
      foreach (f; match_filter) {
        memCacheKey ~= "::" ~ f;
      }
      command.sql = "SELECT " ~ col_filter ~ " FROM " ~ table ~ " WHERE " ~ match_col ~ " IN (" ~ generateSQLParams(match_filter.length) ~ ")";
    } else {
      memCacheKey = col_filter ~ "::" ~ table;
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

    auto cached = cache.get!string(memCacheKey);
    writeln("wtf:", memCacheKey);
    if (!cached) {
      writeln("pushing data to ", memCacheKey, ": ", results);
      if (cache.store(memCacheKey, results) == RETURN_STATE.SUCCESS) {
        cached = cache.get!string(memCacheKey);
      }
    }
    writeln("MEM: ", cached);

  } catch (AssertError e1) {
    return getErrorResponse(e1.msg ~ ": This is a known error with native-mysql. Waiting for it to be fixed.", format);
  } catch (Exception e1) {
    return getErrorResponse(e1.msg, format);
  }

  DataSet node = new DataSet(table).setAttribute("rowsReturned", results.length);

  foreach (row; results) {
    DataSet row_xml = new DataSet("row");

    foreach (foo; results.colNames) {
      auto result_col = new DataSet(foo);
      if (!row.isNull(results.colNameIndicies[foo])) {
        result_col.addCData(row[results.colNameIndicies[foo]].to!string());
      }
      row_xml.addChild(result_col);
    }

    node.addChild(row_xml);
  }

  root.addChild(node);
  return root.getPrettyOutput(format);
}

void lookupItemHandler(HTTPServerRequest req, HTTPServerResponse res) {
  string itemName, item = req.params["item"];
  int action, itemID;
  string format = getFormat(req);

  try {
    itemID = req.params["itemID"].to!int;
    action = ID;
  } catch (ConvException) {
    res.writeBody(getErrorResponse("Not a valid numeric ID: " ~ itemID.to!string, format));
  } catch (RangeError) {
    // ignoring
  }

  try {
    itemName = req.params["itemName"];
    action = NAME;
  } catch (RangeError) {
    // ignoring
  }

  res.writeBody(lookupItem(format, item, itemID, itemName, action));
}

string lookupItem(string format, string item, int itemID, string itemName, int action) {
  struct lookupBy {
    string cn;
    string sc;
  }

  struct lookupType {
    string tn;
    lookupBy[2] a;
    this(string tn, string cn, string sc) {
      this.tn = tn;
      this.a[ID].cn = cn;
      this.a[ID].sc = sc;
    }
  }

  lookupType[string] lookupTable;
  lookupTable["type"] = lookupType("invTypes", "typeName", "typeID");
  lookupTable["item"] = lookupType("invNames", "itemName", "itemID");
  lookupTable["system"] = lookupType("mapSolarSystems", "solarSystemName", "solarSystemID");
  lookupTable["location"] = lookupType("mapDenormalize", "itemName", "itemID");

  foreach(lu; lookupTable) {
    lu.a[NAME].cn = lu.a[ID].sc;
    lu.a[NAME].sc = lu.a[ID].cn;
  }

  string lookup;
  string output;
  string node_attr, node_attr_val;
  Connection c;
  DataSet root = createRootElement;

  try {
    c = getDBConnection();
    scope(exit) c.close();
  } catch (Exception e1) {
    return getErrorResponse(e1.msg, format);
  }

  lookup = item.toLower();

  lookupType* p = (lookup in lookupTable);
  if (p is null) {
    return getErrorResponse("Invalid lookup type: " ~ item, format);
  }

  ResultSet results;

  auto command = new Command(c);
  command.sql = "SELECT " ~ lookupTable[lookup].a[action].cn ~ " FROM " ~ lookupTable[lookup].tn ~ " WHERE " ~ lookupTable[lookup].a[action].sc ~ " = ?";
  command.prepare;

  switch (action) {
    case ID:
      command.bindParameter(itemID, 0);
      results = command.execPreparedResult();
      if (!results.length) {
        return getErrorResponse("No such ID: " ~ itemID.to!string, format);
      }
      try {
        output = results[0][0].get!string;
      } catch (VariantException) {
        // LONGTEXT returns ubyte wihch pisses off conversion
        output = cast(string)results[0][0].get!(ubyte[]);
      }
      node_attr = "id";
      node_attr_val = itemID.to!string;
      break;

    case NAME:
      command.bindParameter(itemName, 0);
      results = command.execPreparedResult();
      if (!results.length) {
        return getErrorResponse("No such Name: " ~ itemName, format);
      }
      output = results[0][0].to!string;
      node_attr = "name";
      node_attr_val = itemName;
      break;

    default:
      return getErrorResponse("This REALLY shouldn't happen, but action is: " ~ action.to!string, format);
  }

  root.addChild(new DataSet(lookupTable[lookup].a[action].cn).setAttribute(node_attr, node_attr_val).setCData(output));
  return root.getPrettyOutput(format);
}

int getDirection(string direction) {
  switch(direction) {
    case "byID":
      return ID;

    case "byName":
      return NAME;

    default:
      return -1;
  }
}

void getBlueprintMatsHandler(HTTPServerRequest req, HTTPServerResponse res) {
  int me, runs, direction = getDirection(req.params["direction"]);

  if (direction == -1) {
    res.writeBody(getErrorResponse("Invalid direction: " ~ req.params["direction"], getFormat(req)));
    return;
  }

  try {
    me = req.query.get("me").to!int;
    if (me > 10) {
      res.writeBody(getErrorResponse("Invalid ME '" ~ me.to!string ~ "', proper values are 1-10", getFormat(req)));
      return;
    }
  } catch (ConvException) {
    me = 0;
  }

  try {
    runs = req.query.get("runs").to!int;
  } catch (ConvException) {
    runs = 1;
  }

  res.writeBody(getBlueprintMats(getFormat(req), req.params["blueprint"], direction, me, runs));
}

string getBlueprintMats(string format, string blueprint, int direction, int me, int runs) {
  DataSet root = createRootElement;
  Connection c;
  int typeID;
  string typeName;

  switch(direction) {
    case ID:
      typeID = blueprint.to!int;
      typeName = lookupItem("text", "type", typeID, null, ID);
      break;

    case NAME:
      typeID = lookupItem("text", "type", 0, blueprint, NAME).to!int;
      typeName = blueprint;
      break;

    default:
      // This won't happen
      break;
  }

  try {
    c = getDBConnection();
    scope(exit) c.close();
  } catch (Exception e1) {
    return getErrorResponse(e1.msg, format);
  }

  ResultSet results;

  auto command = new Command(c);
  command.sql = "SELECT materialTypeID, quantity FROM industryActivityMaterials WHERE typeID = ? AND activityID = 1";
  command.prepare;
  command.bindParameter(typeID, 0);
  results = command.execPreparedResult();

  if (!results.length) {
    return getErrorResponse("Invalid blueprint ID: " ~ typeID.to!string, format);
  }

  string output = typeName ~"\n";
  foreach (row; results) {
    string material = lookupItem("text", "type", row[0].get!int, null, ID);
    int quantity = row[1].get!int;

    root.addChild(new DataSet(material).setCData(quantity.to!string));
  }

  return root.getPrettyOutput(format);
}
