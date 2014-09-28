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
  string DSN = "host=localhost;port=3306;user=eve_static;pwd=eve_static;db=eve_static";
  auto mdb = new MysqlDB(DSN);
  auto c = mdb.lockConnection();
  scope(exit) c.close();

  MetaData md = MetaData(c);
  auto curTables = md.tables();
  XmlNode tables = new XmlNode("tables");
  foreach(tbls ; curTables) {
    tables.addChild(new XmlNode(tbls));
  }

  string table = "warCombatZones";
  ulong rowsAffected;
  auto columns = md.columns(table);
  auto command = new Command(c);
  command.sql = "SELECT * FROM " ~ table;
  //command.prepare();
  //command.bindParameter(table, 0);
  //auto results = command.execPreparedResult();
  auto results = command.execSQLResult();
  XmlNode node = new XmlNode(table);

  foreach (row; results) {
    XmlNode foo = new XmlNode("row");

    foreach(column; columns) {
      if (column.type == "string") {
        foo.addChild(new XmlNode(column.name).addCData(row[column.index].get!string));
      } else {
        foo.addChild(new XmlNode(column.name).addCData(row[column.index].to!string()));
      }
    }

    node.addChild(foo);
  }

  XmlNode root = new XmlNode("eve_static").setAttribute("db_version", "hyperion").setAttribute("error", false);
  root.addChild(node);
	res.writeBody(root.toPrettyString);
}
