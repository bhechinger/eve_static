import vibe.d;
import kxml.xml;
import mysql.connection;
import std.stdio;
import mysql.db;

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
  string DSN = "host=localhost;port=3306;user=eve_static;pwd=eve_static;db=test";
  auto mdb = new MysqlDB(DSN);
  auto c = mdb.lockConnection();
  scope(exit) c.close();

  auto command = new Command(c, "SELECT name, value FROM foo");
  auto results = command.execSQLResult();
  XmlNode node = new XmlNode("thing");
  foreach (row; results) {
    node.addChild(new XmlNode(row[0].get!string).addCData(row[1].get!string));
  }
	res.writeBody(node.toPrettyString);
}
