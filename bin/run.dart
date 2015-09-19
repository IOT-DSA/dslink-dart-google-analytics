import "dart:async";
import "dart:convert";

import "package:googleapis/analytics/v3.dart" as analytics;
import "package:googleapis_auth/src/auth_http_utils.dart";
import "package:http/http.dart" as http;
import "package:googleapis_auth/auth_io.dart";
import "package:dslink/dslink.dart";
import "package:dslink/nodes.dart";

LinkProvider link;

final List<String> SCOPES = [
  analytics.AnalyticsApi.AnalyticsScope
];

main(List<String> args) async {
  link = new LinkProvider(args, "GoogleAnalytics-", defaultNodes: {
    "Add_Account": {
      r"$is": "addAccount",
      r"$name": "Add Account",
      r"$invokable": "write",
      r"$result": "values",
      r"$params": [
        {
          "name": "name",
          "description": "Account Name",
          "type": "string",
          "placeholder": "MyAccount"
        },
        {
          "name": "clientId",
          "description": "Client ID",
          "placeholder": "0123456789.apps.googleusercontent.com",
          "type": "string"
        },
        {
          "name": "clientSecret",
          "description": "Client Secret",
          "placeholder": "my_client_secret",
          "type": "string"
        }
      ],
      r"$columns": [
        {
          "name": "success",
          "type": "bool"
        },
        {
          "name": "message",
          "type": "string"
        }
      ]
    }
  }, profiles: {
    "account": (String path) => new AccountNode(path, link.provider),
    "addAccount": (String path) => new SimpleActionNode(path, (Map<String, dynamic> params) async {
      fail(String msg) {
        return {
          "success": false,
          "message": msg
        };
      }

      String name = params["name"];

      if (name == null || name.isEmpty) {
        return fail("'name' is required");
      }

      if (link["/"].children.containsKey(name)) {
        return fail("Account '${name}' already exists.");
      }

      link.addNode("/${name}", {
        r"$is": "account",
        r"$$client_id": params["clientId"],
        r"$$client_secret": params["clientSecret"]
      });

      link.save();

      return {
        "success": true,
        "message": "Success!"
      };
    }, link.provider),
    "removeAccount": (String path) => new DeleteActionNode.forParent(path, link.provider)
  }, autoInitialize: false, exitOnFailure: true);

  link.init();
  link.connect();
}

class AccountNode extends SimpleNode {
  AutoRefreshingAuthClient client;
  analytics.AnalyticsApi api;

  AccountNode(String path, SimpleNodeProvider provider) : super(path, provider);

  Completer codeCompleter;

  @override
  onCreated() async {
    link.addNode("${path}/Remove", {
      r"$is": "removeAccount",
      r"$invokable": "write",
      r"$name": "Remove Account"
    });

    var clientId = configs[r"$$client_id"];
    var clientSecret = configs[r"$$client_secret"];
    var refreshToken = configs[r"$$refresh_token"];

    var cid = new ClientId(clientId, clientSecret);

    if (refreshToken == null) {
      var authUrlNode = createChild("Authorization_Url", {
        r"$name": "Authorization Url",
        r"$type": "string"
      })..serializable = false;

      client = await clientViaUserConsentManual(cid, SCOPES, (uri) {
        var u = Uri.parse(uri);

        var params = new Map.from(u.queryParameters);

        params["access_type"] = "offline";

        if (u.queryParameters["access_type"] != "offline") {
          u = u.replace(queryParameters: params);
        }

        uri = u.toString();

        authUrlNode.updateValue(uri);
        codeCompleter = new Completer();

        var setAuthorizationCodeNode = new SimpleActionNode(
          "${path}/Set_Authorization_Code", (
          Map<String, dynamic> params) async {
          var code = params["code"];

          if (code == null || code.isEmpty) {
            return null;
          }

          if (codeCompleter != null && !codeCompleter.isCompleted) {
            codeCompleter.complete(code);
          }
        }, provider);

        setAuthorizationCodeNode.serializable = false;

        setAuthorizationCodeNode.load({
          r"$name": "Set Authorization Code",
          r"$invokable": "write",
          r"$result": "values",
          r"$params": [
            {
              "name": "code",
              "type": "string",
              "description": "Authorization Code",
              "placeholder": "4/v6xr77ewYqhvHSyW6UJ1w7jKwAzu"
            }
          ]
        });

        provider.setNode(setAuthorizationCodeNode.path, setAuthorizationCodeNode);

        return codeCompleter.future;
      });

      configs[r"$$refresh_token"] = client.credentials.refreshToken;
      link.save();

      provider.removeNode("${path}/Set_Authorization_Code");
      provider.removeNode("${path}/Authorization_Url");

      init();
    } else {
      var creds = new AccessCredentials(
        new AccessToken("", "", new DateTime.now().toUtc()),
        refreshToken,
        SCOPES
      );
      var baseClient = new http.Client();
      creds = await refreshCredentials(cid, creds, baseClient);
      client = new AutoRefreshingClient(baseClient, cid, creds);
      init();
    }
  }

  init() async {
    api = new analytics.AnalyticsApi(client);

    var getDataResultNode = new SimpleActionNode("${path}/Get_Data", (Map<String, dynamic> params) async {
      var ids = params["ids"];
      var startDate = params["startDate"];
      var endDate = params["endDate"];
      var metrics = params["metrics"];
      var dims = params["dimensions"];
      var data = await api.data.ga.get(ids, startDate, endDate, metrics, output: "json", dimensions: dims);
      var columns = [];
      data.columnHeaders.forEach((x) {
        columns.add(new TableColumn(x.name, "dynamic"));
      });
      return new Table(columns, data.rows);
    })..load({
      r"$name": "Get Data",
      r"$invokable": "read",
      r"$result": "table",
      r"$params": [
        {
          "name": "ids",
          "type": "string"
        },
        {
          "name": "startDate",
          "type": "string"
        },
        {
          "name": "endDate",
          "type": "string"
        },
        {
          "name": "metrics",
          "type": "string"
        },
        {
          "name": "dimensions",
          "type": "string"
        }
      ]
    });

    provider.setNode(getDataResultNode.path, getDataResultNode);
  }

  @override
  onRemoving() {
    if (client != null) {
      client.close();
    }
  }
}