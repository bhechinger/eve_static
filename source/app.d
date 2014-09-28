import vibe.d;
import kxml.xml;
import mysql.connection;
import std.stdio;
import mysql.db;
import std.conv;

MysqlDB mdb;

shared static this() {
	auto settings = new HTTPServerSettings;
	settings.port = 8181;
	settings.bindAddresses = ["::1", "127.0.0.1"];

  // CREATE USER 'eve_static'@'localhost' IDENTIFIED BY 'eve_static';
  // GRANT ALL PRIVILEGES ON eve_static.* TO 'eve_static'@'localhost'
  try {
    string DSN = "host=localhost;port=3306;user=eve_static;pwd=eve_static;db=eve_static";
    mdb = new MysqlDB(DSN);
  } catch (Exception e1) {
    // Now what, though. How do we inform the client?
    logError("Exception: " ~ e1.msg);
  }

  auto router = new URLRouter;
  router.get("/tables/list", &getTableList);
  router.get("/table/:tableName", &getTable);
  router.get("/columns/:tableName", &getColumnList);
	listenHTTP(settings, router);

	logInfo("Please open http://127.0.0.1:8181/ in your browser.");
}

void getTableList(HTTPServerRequest req, HTTPServerResponse res) {
  auto c = mdb.lockConnection();
  scope(exit) c.close();
  XmlNode root = new XmlNode("eve_static").setAttribute("db_version", "hyperion").setAttribute("error", false);

  try {
    MetaData md = MetaData(c);
    auto curTables = md.tables();
    XmlNode tables = new XmlNode("tables");
    foreach(tbls ; curTables) {
      tables.addChild(new XmlNode(tbls));
    }
    root.addChild(tables);
  } catch (Exception e1) {
    root.setAttribute("error", true);
    root.addChild(new XmlNode("error").addCData(e1.msg));
    logError("Exception: " ~ e1.msg);
  }
	res.writeBody(root.toPrettyString);
}

void getColumnList(HTTPServerRequest req, HTTPServerResponse res) {
  string table = req.params["tableName"];
  auto c = mdb.lockConnection();
  scope(exit) c.close();
  XmlNode root = new XmlNode("eve_static").setAttribute("db_version", "hyperion").setAttribute("error", false);

  try {
    MetaData md = MetaData(c);
    auto curColumns = md.columns(table);
    XmlNode columns = new XmlNode("columns").setAttribute("table", table);
    foreach(cols; curColumns) {
      columns.addChild(new XmlNode(cols.name));
    }
    root.addChild(columns);
  } catch (Exception e1) {
    root.setAttribute("error", true);
    root.addChild(new XmlNode("error").addCData(e1.msg));
    logError("Exception: " ~ e1.msg);
  }
	res.writeBody(root.toPrettyString);
}

void getTable(HTTPServerRequest req, HTTPServerResponse res) {
  string table = req.params["tableName"];
  bool table_found = false;
  auto c = mdb.lockConnection();
  scope(exit) c.close();
  MetaData md;

  XmlNode root = new XmlNode("eve_static").setAttribute("db_version", "hyperion").setAttribute("error", false);

  try {
    md = MetaData(c);
    auto curTables = md.tables();
    foreach(tbls ; curTables) {
      if (table == tbls) {
        table_found = true;
      }
    }
  } catch (Exception e1) {
    root.setAttribute("error", true);
    root.addChild(new XmlNode("error").addCData(e1.msg));
    logError("Exception: " ~ e1.msg);
    res.writeBody(root.toPrettyString);
    return;
  }

  if (!table_found) {
    root.setAttribute("error", true);
    root.addChild(new XmlNode("error").addCData("No such table: " ~ table));
    res.writeBody(root.toPrettyString);
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
    root.setAttribute("error", true);
    root.addChild(new XmlNode("error").addCData(e1.msg));
    logError("Exception: " ~ e1.msg);
    res.writeBody(root.toPrettyString);
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
