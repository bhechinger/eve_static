import vibe.d;
import kxml.xml;
import mysql.connection;
import std.stdio;
import mysql.db;
import std.conv;

MysqlDB mdb;
string db_version = "hyperion_1.0";
string[] curTables;
MetaData md;
bool refresh_db = true;

Connection getDBConnection() {
  Connection c;

  try {
    if (refresh_db) {
      string DSN = "host=localhost;port=3306;user=eve_static;pwd=eve_static;db=eve_static";
      mdb = new MysqlDB(DSN);
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

  getDBConnection();

  auto router = new URLRouter;
  router.get("/tables/list", &getTableList);
  router.get("/table/:tableName", &getTable);
  router.get("/columns/:tableName", &getColumnList);
	listenHTTP(settings, router);

	logInfo("Please open http://127.0.0.1:8181/ in your browser.");
}

XmlNode createRootElement() {
  return(new XmlNode("eve_static").setAttribute("db_version", db_version).setAttribute("error", false));
}

string sendErrorResponse(string msg) {
  refresh_db = true;
  XmlNode root = createRootElement();
  root.setAttribute("error", true);
  root.addChild(new XmlNode("error").addCData(msg));
  logError("Exception: " ~ msg);
  return(root.toPrettyString);
}

void getTableList(HTTPServerRequest req, HTTPServerResponse res) {
  XmlNode root = createRootElement();
  Connection c;

  try {
    c = getDBConnection();
    scope(exit) c.close();

    XmlNode tables = new XmlNode("tables");
    foreach(tbls ; curTables) {
      tables.addChild(new XmlNode(tbls));
    }
    root.addChild(tables);
	  res.writeBody(root.toPrettyString);
  } catch (Exception e1) {
    res.writeBody(sendErrorResponse(e1.msg));
  }
}

void getColumnList(HTTPServerRequest req, HTTPServerResponse res) {
  string table = req.params["tableName"];
  XmlNode root = createRootElement();

  try {
    auto curColumns = md.columns(table);
    XmlNode columns = new XmlNode("columns").setAttribute("table", table);
    foreach(cols; curColumns) {
      columns.addChild(new XmlNode(cols.name));
    }
    root.addChild(columns);
	  res.writeBody(root.toPrettyString);
  } catch (Exception e1) {
    res.writeBody(sendErrorResponse(e1.msg));
  }
}

void getTable(HTTPServerRequest req, HTTPServerResponse res) {
  string table = req.params["tableName"];
  bool table_found = false;
  Connection c;
  XmlNode root = new XmlNode("eve_static").setAttribute("db_version", db_version).setAttribute("error", false);

  try {
    c = getDBConnection();
    scope(exit) c.close();

    foreach(tbls ; curTables) {
      if (table == tbls) {
        table_found = true;
      }
    }
  } catch (Exception e1) {
    res.writeBody(sendErrorResponse(e1.msg));
    return;
  }

  if (!table_found) {
    res.writeBody(sendErrorResponse("No such table: " ~ table));
    return;
  }

  ResultSet results;
  ColumnInfo[] curColumns;
  try {
    curColumns = md.columns(table);
    //pragma(msg, typeof(curColumns))
    auto command = new Command(c);
    command.sql = "SELECT * FROM " ~ table;
    results = command.execSQLResult();
  } catch (Exception e1) {
    res.writeBody(sendErrorResponse(e1.msg));
    return;
  }

  XmlNode node = new XmlNode(table).setAttribute("rowsReturned", results.length);

  foreach (row; results) {
    XmlNode foo = new XmlNode("row");

    foreach(column; curColumns) {
      if (column.type == "string") {
        foo.addChild(new XmlNode(column.name).addCData(row[column.index].get!string));
      } else {
        foo.addChild(new XmlNode(column.name).addCData(row[column.index].to!string()));
      }
    }

    node.addChild(foo);
  }

  root.addChild(node);
	res.writeBody(root.toPrettyString);
}
