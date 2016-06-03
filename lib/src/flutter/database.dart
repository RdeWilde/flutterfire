library firebase.flutter.database;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../generated/firebase.mojom.dart' as mojom;
import '../database.dart';
import '../data_snapshot.dart';
import '../event.dart';
import 'app.dart';
import 'conversions.dart';
import 'data_snapshot.dart';

abstract class FirebaseDatabaseImpl implements FirebaseDatabase {
  static final FirebaseDatabase instance = new _FlutterFirebaseDatabase(FirebaseAppImpl.instance);
}

class _FlutterFirebaseDatabase extends FirebaseDatabaseImpl {

  _FlutterFirebaseDatabase(this.app)
    : proxy = new mojom.DatabaseReferenceProxy.unbound() {
    app.proxy.reference(proxy);
  }

  final FirebaseAppImpl app;
  final mojom.DatabaseReferenceProxy proxy;

  DatabaseReference reference([ String path ]) {
    DatabaseReference root = new _FlutterDatabaseReference(this, <String>[]);
    if (path != null)
      return root.child(path);
    else
      return root;
  }
}

class _FlutterDatabaseReference extends _FlutterQuery implements DatabaseReference {
  _FlutterDatabaseReference(_FlutterFirebaseDatabase database, List<String> path)
    : super(database, path);

  DatabaseReference child(String path) {
    return new _FlutterDatabaseReference(
      database,
      (new List<String>.from(_path)..addAll(path.split("/")))
    );
  }

  DatabaseReference parent() {
    return new _FlutterDatabaseReference(
      database,
      (new List<String>.from(_path)..removeLast())
    );
  }

  DatabaseReference root() {
    return new _FlutterDatabaseReference(database, <String>[]);
  }

  String get key {
    if (_path != null)
      return _path.last;
    throw new UnsupportedError("Autogenerated child key is not available yet");
  }

  String toString() => "$runtimeType($path)";

  Future set(value) => setWithPriority(value, null);

  Future remove() {
    Completer completer = new Completer();
    _proxy
      .removeValue(path)
      .then(getResultCallback(completer));
    return completer.future;
  }

  DatabaseReference push() {
    _FlutterDatabaseReference child =
      new _FlutterDatabaseReference(database, null);
    child._proxy = new mojom.DatabaseReferenceProxy.unbound();
    _proxy.push(path, child._proxy)
      .then((mojom.DatabaseReferencePushResponseParams params) {
      // Once we know the path of the new node, we can dispose
      // of the Mojo object rather than leaking it
      child._proxy.close(immediate: true);
      child._proxy = _proxy;
      child._path = new List<String>.from(_path)..add(params.key);
    });
    return child;
  }

  Future setWithPriority(value, int priority) {
    Completer completer = new Completer();
    String jsonValue = JSON.encode({ "value": value });
    _proxy.setValue(path, jsonValue, priority ?? 0, priority != null)
      .then(getResultCallback(completer));
    return completer.future;
  }

  Future setPriority(int priority) {
    Completer completer = new Completer();
    _proxy
      .setPriority(path, priority)
      .then(getResultCallback(completer));
    return completer.future;
  }
}

class _ValueEventListener implements mojom.ValueEventListener {
  StreamController<Event> _controller;
  _ValueEventListener(this._controller);

  void onCancelled(mojom.Error error) {
    print("ValueEventListener onCancelled: ${error}");
    _controller.close();
  }

  void onDataChange(mojom.DataSnapshot snapshot) {
    Event event = new Event(new FlutterDataSnapshot.fromFlutterObject(snapshot), null);
    _controller.add(event);
  }
}

class _ChildEvent extends Event {
  _ChildEvent(this.eventType, DataSnapshot snapshot, [ String prevChild ])
    : super(snapshot, prevChild);
  final mojom.EventType eventType;
}

class _ChildEventListener implements mojom.ChildEventListener {
  final StreamController<Event> _controller;
  _ChildEventListener(this._controller);

  void onCancelled(mojom.Error error) {
    print("ChildEventListener onCancelled: ${error}");
    _controller.close();
  }

  void onChildAdded(mojom.DataSnapshot snapshot, String prevSiblingKey) {
    _ChildEvent event = new _ChildEvent(
      mojom.EventType.eventTypeChildAdded,
      new FlutterDataSnapshot.fromFlutterObject(snapshot),
      prevSiblingKey
    );
    _controller.add(event);
  }

  void onChildMoved(mojom.DataSnapshot snapshot, String prevSiblingKey) {
    _ChildEvent event = new _ChildEvent(
      mojom.EventType.eventTypeChildMoved,
      new FlutterDataSnapshot.fromFlutterObject(snapshot),
      prevSiblingKey
    );
    _controller.add(event);
  }

  void onChildChanged(mojom.DataSnapshot snapshot, String prevSiblingKey) {
    _ChildEvent event = new _ChildEvent(
      mojom.EventType.eventTypeChildChanged,
      new FlutterDataSnapshot.fromFlutterObject(snapshot),
      prevSiblingKey
    );
    _controller.add(event);
  }

  void onChildRemoved(mojom.DataSnapshot snapshot) {
    _ChildEvent event = new _ChildEvent(
      mojom.EventType.eventTypeChildRemoved,
      new FlutterDataSnapshot.fromFlutterObject(snapshot)
    );
    _controller.add(event);
  }
}

class _FlutterQuery implements Query {
  _FlutterQuery(_FlutterFirebaseDatabase database, this._path)
    : database = database,
      _proxy = database.proxy;

  final _FlutterFirebaseDatabase database;

  mojom.DatabaseReferenceProxy _proxy;

  List<String> _path;
  String get path => _path?.join("/") ?? '';

  Stream<Event> _onValue;
  Stream<Event> get onValue {
    if (_onValue == null) {
      mojom.ValueEventListener listener;
      mojom.ValueEventListenerStub stub;
      StreamController<Event> controller = new StreamController<Event>.broadcast(
        onListen: () {
          stub = new mojom.ValueEventListenerStub.unbound(listener);
          _proxy.addValueEventListener(path, stub);
        },
        sync: true
      );
      listener = new _ValueEventListener(controller);
      _onValue = controller.stream;
    }
    return _onValue;
  }

  Stream<Event> _onChildEvent;
  Stream<Event> _on(mojom.EventType eventType) {
    if (_onChildEvent == null) {
      mojom.ChildEventListener listener;
      mojom.ChildEventListenerStub stub;
      StreamController<Event> controller = new StreamController<Event>.broadcast(
        onListen: () {
          stub = new mojom.ChildEventListenerStub.unbound(listener);
          _proxy.addChildEventListener(path, stub);
        },
        sync: true
      );
      listener = new _ChildEventListener(controller);
      _onChildEvent = controller.stream;
    }
    return _onChildEvent.where((_ChildEvent event) => event.eventType == eventType);
  }

  Stream<Event> get onChildAdded => _on(mojom.EventType.eventTypeChildAdded);
  Stream<Event> get onChildMoved => _on(mojom.EventType.eventTypeChildMoved);
  Stream<Event> get onChildChanged => _on(mojom.EventType.eventTypeChildChanged);
  Stream<Event> get onChildRemoved => _on(mojom.EventType.eventTypeChildRemoved);

  /**
   * Listens for exactly one event of the specified event type, and then stops
   * listening.
   */
  Future<DataSnapshot> once(String eventType) async {
    mojom.EventType mojoEventType;
    switch(eventType) {
      case "value":
        mojoEventType = mojom.EventType.eventTypeValue;
        break;
      case "child_added":
        mojoEventType = mojom.EventType.eventTypeChildAdded;
        break;
      case "child_changed":
        mojoEventType = mojom.EventType.eventTypeChildChanged;
        break;
      case "child_removed":
        mojoEventType = mojom.EventType.eventTypeChildRemoved;
        break;
      case "child_moved":
        mojoEventType = mojom.EventType.eventTypeChildMoved;
        break;
      default:
        assert(false);
        return null;
    }
    mojom.DataSnapshot result =
      (await _proxy.observeSingleEventOfType(path, mojoEventType)).snapshot;
    return new FlutterDataSnapshot.fromFlutterObject(result);
  }
}
