import 'dart:async';
import 'dart:math';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_analytics/observer.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

void main() => runApp(new ChatApp());

final ThemeData kIOSTheme = new ThemeData(
  primarySwatch: Colors.orange,
  primaryColor: Colors.grey[100],
  primaryColorBrightness: Brightness.light,
);

final ThemeData kDefaultTheme = new ThemeData(
  primarySwatch: Colors.purple,
  accentColor: Colors.blueAccent[400],
);

final googleSignIn = new GoogleSignIn();
final analytics = new FirebaseAnalytics();
final auth = FirebaseAuth.instance;
final DocumentReference documentReference =
    Firestore.instance.document('data/messages');
File image;

class ChatApp extends StatelessWidget {
  static FirebaseAnalyticsObserver observer =
      new FirebaseAnalyticsObserver(analytics: analytics);

  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      title: 'FriendlyChat',
      theme: defaultTargetPlatform == TargetPlatform.iOS
          ? kIOSTheme
          : kDefaultTheme,
      navigatorObservers: <NavigatorObserver>[observer],
      home: new ChatScreen(analytics: analytics, observer: observer),
    );
  }
}

Future<Null> _ensureLoggedIn() async {
  GoogleSignInAccount user = googleSignIn.currentUser;
  if (user == null) user = await googleSignIn.signInSilently();
  if (user == null) {
    await googleSignIn.signIn();
    analytics.logLogin();
  }
  if (await auth.currentUser() == null) {
    GoogleSignInAuthentication credentials =
        await googleSignIn.currentUser.authentication;
    await auth.signInWithGoogle(
      idToken: credentials.idToken,
      accessToken: credentials.accessToken,
    );
  }
}

class ChatMessage extends StatelessWidget {
  ChatMessage({this.text, this.animationController});

  final AnimationController animationController;
  final String text;

  @override
  Widget build(BuildContext context) {
    return new SizeTransition(
        sizeFactor: new CurvedAnimation(
            parent: animationController, curve: Curves.easeOut),
        axisAlignment: 0.0,
        child: new Container(
            margin: const EdgeInsets.symmetric(vertical: 10.0),
            child: new Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                new Container(
                    margin: const EdgeInsets.only(right: 16.0),
                    child: new CircleAvatar(
                      backgroundImage:
                          new NetworkImage(googleSignIn.currentUser.photoUrl),
                    )),
                new Expanded(
                  child: new Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      new Text(
                        googleSignIn.currentUser.displayName,
                        style: new TextStyle(color: Colors.blue),
                      ),
                      new Container(
                        margin: const EdgeInsets.only(top: 6.0),
                        child: new Text(text),
                      )
                    ],
                  ),
                )
              ],
            )));
  }
}

class ChatScreen extends StatefulWidget {
  final FirebaseAnalytics analytics;
  final FirebaseAnalyticsObserver observer;

  ChatScreen({this.analytics, this.observer});

  @override
  State createState() => new ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _textController = new TextEditingController();
  final List<ChatMessage> _messages = <ChatMessage>[];
  bool _isComposing = false;

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
        title: new Text('FriendlyChat'),
        elevation: Theme.of(context).platform == TargetPlatform.iOS ? 0.0 : 4.0,
      ),
      body: new Container(
        child: new Column(
          children: <Widget>[
            new Flexible(
                child: new ListView.builder(
              padding: new EdgeInsets.all(8.0),
              reverse: true,
              itemBuilder: (_, int index) => _messages[index],
              itemCount: _messages.length,
            )),
            new Divider(
              height: 1.0,
            ),
            new Container(
              decoration: new BoxDecoration(color: Theme.of(context).cardColor),
              child: _buildTextComposer(),
            )
          ],
        ),
        decoration: Theme.of(context).platform == TargetPlatform.iOS
            ? new BoxDecoration(
                border:
                    new Border(top: new BorderSide(color: Colors.grey[200])))
            : null,
      ),
    );
  }

  Widget _buildTextComposer() {
    return new IconTheme(
        data: new IconThemeData(color: Theme.of(context).accentColor),
        child: new Container(
            margin: const EdgeInsets.symmetric(horizontal: 8.0),
            child: new Row(
              children: <Widget>[
                new Container(
                  margin: new EdgeInsets.symmetric(horizontal: 4.0),
                  child: new IconButton(
                      icon: new Icon(Icons.photo_camera),
                      onPressed: () async {
                        await _ensureLoggedIn();
                        File imageFile = await ImagePicker.pickImage(
                            source: ImageSource.gallery);

                        if (imageFile != null) {
                          image = imageFile;
                          setState(() {});
                        }
                        int random = new Random().nextInt(100000);
                        StorageReference ref = FirebaseStorage.instance
                            .ref()
                            .child("image_$random.jpg");
                        StorageUploadTask uploadTask = ref.putFile(imageFile);
                        Uri downloadUrl = (await uploadTask.future).downloadUrl;
                        _uploadImage(imageUrl: downloadUrl.toString());
                      }),
                ),
                new Flexible(
                  child: new TextField(
                    controller: _textController,
                    onChanged: (String text) {
                      setState(() {
                        _isComposing = text.length > 0;
                      });
                    },
                    onSubmitted: _handleSubmitted,
                    decoration: new InputDecoration.collapsed(
                        hintText: "Send a message"),
                  ),
                ),
                new Container(
                    margin: new EdgeInsets.symmetric(horizontal: 4.0),
                    child: Theme.of(context).platform == TargetPlatform.iOS
                        ? new CupertinoButton(
                            child: new Text('Send'),
                            onPressed: _isComposing
                                ? () => _handleSubmitted(_textController.text)
                                : null,
                          )
                        : new IconButton(
                            icon: new Icon(Icons.send),
                            onPressed: _isComposing
                                ? () => _handleSubmitted(_textController.text)
                                : null)),
              ],
            )));
  }

  Future<Null> _handleSubmitted(String text) async {
    _textController.clear();
    setState(() {
      _isComposing = false;
    });

    await _ensureLoggedIn();
    _sendMessage(text: text);
  }

  void _sendMessage({String text}) {
    ChatMessage message = new ChatMessage(
      text: text,
      animationController: new AnimationController(
          duration: new Duration(milliseconds: 700), vsync: this),
    );

      setState(() {
        _messages.insert(0, message);
      });
      message.animationController.forward();

    documentReference.updateData({
      'photoUrl': googleSignIn.currentUser.photoUrl,
      'name': googleSignIn.currentUser.displayName,
      'message': text,
    }).whenComplete(() {
      print('Document added');
    }).catchError((e) => print(e));
  }

  void _uploadImage({String imageUrl}) {
    documentReference.updateData({
      'imageUrl': imageUrl,
    }).whenComplete(() {
      print('Image uploaded');
    }).catchError((e) => print(e));
  }

  @override
  void dispose() {
    for (ChatMessage message in _messages)
      message.animationController.dispose();
    super.dispose();
  }
}
