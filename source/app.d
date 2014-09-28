import vibe.d;
import kxml.xml;
import mysql.connection;
import std.stdio;
import mysql.db;
import std.conv;

shared static this() {
	auto settings = new HTTPServerSettings;
	settings.port = 8181;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	listenHTTP(settings, &hello);

	logInfo("Please open http://127.0.0.1:8181/ in your browser.");
}

void hello(HTTPServerRequest req, HTTPServerResponse res) {
  // CREATE USER 'eve_static'@'localhost' IDENTIFIED BY 'eve_static';
  // GRANT ALL PRIVILEGES ON eve_static.* TO 'eve_static'@'localhost'
  string table = "warCombatZones";
  bool table_found = false;
  string DSN = "host=localhost;port=3306;user=eve_static;pwd=eve_static;db=eve_static";
  auto mdb = new MysqlDB(DSN);
  auto c = mdb.lockConnection();
  scope(exit) c.close();

  XmlNode root = new XmlNode("eve_static").setAttribute("db_version", "hyperion").setAttribute("error", false);

  MetaData md = MetaData(c);
  auto curTables = md.tables();
  XmlNode tables = new XmlNode("tables");
  foreach(tbls ; curTables) {
    if (table == tbls) {
        table_found = true;
    }
    tables.addChild(new XmlNode(tbls));
  }
  //root.addChild(tables);

  if (!table_found) {
    root.setAttribute("error", true);
    root.addChild(new XmlNode("error").addCData("No such table: " ~ table));
    res.writeBody(root.toPrettyString);
    return;
  }

  auto curColumns = md.columns(table);
  XmlNode columns = new XmlNode("columns");
  foreach(cols; curColumns) {
      columns.addChild(new XmlNode(cols.name));
  }
  //root.addChild(columns);

  auto command = new Command(c);
  command.sql = "SELECT * FROM " ~ table;
  auto results = command.execSQLResult();
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
