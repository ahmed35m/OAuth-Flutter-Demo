import 'package:flutter/material.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../component/Login.dart';
import '../component/Profile.dart';

final FlutterAppAuth appAuth = FlutterAppAuth();
final FlutterSecureStorage secureStorage = const FlutterSecureStorage();

/// -----------------------------------
///           Auth0 Variables
/// -----------------------------------
const AUTH0_DOMAIN = '';
const AUTH0_CLIENT_ID = '';

const AUTH0_REDIRECT_URI = 'com.auth0.flutterdemo://login-callback';
const AUTH0_ISSUER = 'https://$AUTH0_DOMAIN';

/// -----------------------------------

//------------------------------------------
//          Login Page
//------------------------------------------
class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  _LoginPageState createState() => _LoginPageState();
}

//--------Page State------------------------
class _LoginPageState extends State<LoginPage> {
  bool isBusy = false;
  bool isLoggedIn = false;
  String? errorMessage;
  String? name = "no one";
  String? picture = "";

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Auth0 Demo',
      home: Scaffold(
          appBar: AppBar(
            title: Text('Auth0 Demo'),
          ),
          body: Column(children: [
            (Center(
              child: isBusy
                  ? CircularProgressIndicator()
                  : isLoggedIn
                      ? Profile(logoutAction, name: name)
                      : Login(loginAction, errorMessage),
            )),
            Text('Logged In Status: ${isLoggedIn}')
          ])),
    );
  }

// Name: parseIdToken
// Purpose: Return decoded JSON as a Map
  Map<String, dynamic> parseIdToken(String? idToken) {
    if (idToken == null) {
      idToken = 'Test';
    }

    final parts = idToken.split(r'.');
    assert(parts.length == 3);

    return jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
  }

// Name: getUserDetails
// Purpose: Makes get request to retrieve user details, ensure domain url is set
  Future<Map<String, dynamic>> getUserDetails(String? accessToken) async {
    final Uri url = Uri.parse('https://$AUTH0_DOMAIN/userinfo');
    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get user details');
    }
  }

// Name: loginAction
// Purpose: Makes authentication request
  Future<void> loginAction() async {
    setState(() {
      isBusy = true;
      errorMessage = '';
    });

    // Authentication Request
    try {
      print("Loging in ....");
      final AuthorizationTokenResponse? result =
          await appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(AUTH0_CLIENT_ID, AUTH0_REDIRECT_URI,
            issuer: 'https://$AUTH0_DOMAIN',
            scopes: ['openid', 'profile', 'offline_access'],
            promptValues: ['login']),
      );
      print(result!.accessTokenExpirationDateTime);
      final idToken = parseIdToken(result.idToken);
      print(idToken);
      print(result.accessToken);

      // Use access token for user detials authorization
      final profile = await getUserDetails(result.accessToken);

      // Store refresh toke in secure storage
      // TODO: replace secureStorage with Hive encrypted box
      await secureStorage.write(
          key: 'refresh_token', value: result.refreshToken);

      // Update Component state
      // TODO: Push navigate stack to home page
      setState(() {
        isBusy = false;
        isLoggedIn = true;
        name = idToken['name'];
        picture = profile['picture'];

        print("Login Status ${isLoggedIn}");
      });
    } catch (e, s) {
      print('login error: $e - stack: $s');

      setState(() {
        isBusy = false;
        isLoggedIn = false;
        errorMessage = e.toString();
      });
    }
  }

// Name: logoutAction
// Purpose: Removes refresh token from storage
// TODO: Make a get request to endpoint for logout
  void logoutAction() async {
    await secureStorage.delete(key: 'refresh_token');
    setState(() {
      isLoggedIn = false;
      isBusy = false;
    });
  }

  @override
  void initState() {
    initAction();
    super.initState();
  }

  void initAction() async {
    final storedRefreshToken = await secureStorage.read(key: 'refresh_token');
    // ignore: unnecessary_null_comparison
    if (storedRefreshToken == null) return;

    setState(() {
      isBusy = true;
    });

    try {
      final response = await appAuth.token(TokenRequest(
        AUTH0_CLIENT_ID,
        AUTH0_REDIRECT_URI,
        issuer: AUTH0_ISSUER,
        refreshToken: storedRefreshToken,
      ));

      if (response != null) {
        final idToken = parseIdToken(response.idToken);

        final profile = await getUserDetails(response.accessToken);

        secureStorage.write(key: 'refresh_token', value: response.refreshToken);

        setState(() {
          isBusy = false;
          isLoggedIn = true;
          name = idToken['name'];
          picture = profile['picture'];
        });
      }
    } catch (e, s) {
      print('error on refresh token: $e - stack: $s');
      logoutAction();
    }
  }
}
