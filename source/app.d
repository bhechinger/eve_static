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

  auto command = new Command(c, "SELECT combatZoneID, combatZoneName, factionID, centerSystemID, description FROM warCombatZones");
  auto results = command.execSQLResult();
  XmlNode node = new XmlNode("warCombatZones");
  foreach (row; results) {
    XmlNode foo = new XmlNode(row[1].get!string);
    foo.addChild(new XmlNode("description").addCData(row[4].get!string));
    foo.addChild(new XmlNode("combatZoneID").addCData(to!string(row[0].get!int)));
    foo.addChild(new XmlNode("factionID").addCData(to!string(row[2].get!int)));
    foo.addChild(new XmlNode("centerSystemID").addCData(to!string(row[3].get!int)));
    node.addChild(foo);
  }
	res.writeBody(node.toPrettyString);
}
