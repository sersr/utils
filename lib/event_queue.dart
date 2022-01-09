library event_queue;

import 'dart:async';
import 'dart:collection';

import 'package:utils/utils.dart';

final _zoneToken = Object();

/// [_TaskEntry._run]
typedef EventCallback<T> = FutureOr<T> Function();
typedef EventRunCallback<T> = Future<void> Function(_TaskEntry<T> task);

/// 以队列的形式进行并等待异步任务
///
/// 目的: 确保任务之间的安全性
///
/// 如果一个异步任务被调用多次或多个异步任务访问相同的数据对象，
/// 那么在这个任务中所使用的的数据对象将变得不稳定
///
/// 异步任务不超过 [channels]
/// 如果 [channels] == 1, 那么任务之间所操作的数据是稳定的，除非任务不在队列中
///
/// 允许 [addOneEventTask], [addEventTask] 交叉使用
class EventQueue {
  EventQueue({this.channels = 1});

  ///所有任务即时运行，[channels] 无限制
  EventQueue.all() : channels = -1;
  final int channels;

  _ChannelState _getState() {
    if (channels < 1) {
      return _ChannelState.run;
    } else if (channels > 1) {
      return _ChannelState.limited;
    } else {
      return _ChannelState.one;
    }
  }

  static _TaskEntry? get currentTask {
    final _t = Zone.current[_zoneToken];
    if (_t is _TaskEntry) return _t;
    return null;
  }

  static final _tempQueues = <Object, EventQueue>{};
  static int delayRemove = 5000;

  static bool printWhereUseEventQueue = false;

  static S _runTask<S>(key, S Function(EventQueue event) run,
      {int channels = 1}) {
    final listKey = ListKey([key, channels]);

    final _queue = _tempQueues.putIfAbsent(listKey, () {
      assert(!printWhereUseEventQueue || Log.log(Log.warn, '.', position: 4));
      return EventQueue(channels: channels);
    });
    return run(_queue)
      ..whenComplete(() {
        _queue.runner.whenComplete(() {
          Timer(Duration(milliseconds: delayRemove <= 0 ? 0 : delayRemove), () {
            final _q = _tempQueues[listKey];
            if (!_queue.actived && _q == _queue) {
              _tempQueues.remove(listKey);
            }
          });
        });
      });
  }

  /// 拥有相同的[key]在会一个队列中
  ///
  /// 如果所有任务都已完成，移除[EventQueue]对象
  static Future<T> run<T>(key, EventCallback<T> task, {int channels = 1}) {
    return _runTask(key, (event) => event.awaitTask(task), channels: channels);
  }

  static Future<T?> runOne<T>(key, EventCallback<T> task, {int channels = 1}) {
    return _runTask(key, (event) => event.awaitOne(task), channels: channels);
  }

  static void push<T>(key, EventCallback<T> task, {int channels = 1}) {
    return _runTask(key, (event) => event.addEventTask(task),
        channels: channels);
  }

  static void pushOne<T>(key, EventCallback<T> task, {int channels = 1}) {
    _runTask(key, (event) => event.addOneEventTask(task), channels: channels);
  }

  static Future<void> getQueueRunner(key, {int channels = 1}) {
    final listKey = ListKey([key, channels]);

    return _tempQueues[listKey]?.runner ?? Future.value(null);
  }

  static bool getQueueState(key, {int channels = 1}) {
    final listKey = ListKey([key, channels]);
    return _tempQueues[listKey]?.actived ?? false;
  }

  static int checkTempQueueLength() {
    return _tempQueues.length;
  }

  final _taskPool = ListQueue<_TaskEntry>();

  bool get isLast => _taskPool.isEmpty;

  Future<void>? _runner;
  Future<void>? get runner => _runner;

  bool _active = false;
  bool get actived => _active;

  Future<T> _addEventTask<T>(EventCallback<T> callback,
      {bool onlyLastOne = false, Object? taskKey}) {
    final _task = _TaskEntry<T>(
      queue: this,
      taskKey: taskKey,
      callback: callback,
      onlyLastOne: onlyLastOne,
    );
    _taskPool.add(_task);

    final key = _task.taskKey;
    final future = _task.future;
    if (key != null) {
      final keyList = _keyEvents.putIfAbsent(key, () => <_TaskEntry>{});
      if (keyList.isEmpty) {
        _task._taskIgnore = _TaskIgnore(true);
      } else {
        assert(keyList.first._taskIgnore != null);
        _task._taskIgnore = keyList.first._taskIgnore;
      }
      keyList.add(_task);
      future.whenComplete(() {
        keyList.remove(_task);
        if (keyList.isEmpty) {
          _keyEvents.remove(key);
        }
      });
    }
    _start();
    return future;
  }

  void addEventTask<T>(EventCallback<T> callback, {Object? taskKey}) =>
      _addEventTask(callback, taskKey: taskKey);

  /// 如果该任务在队列中，并且不是最后一个，那么将被抛弃。
  ///
  /// 例外:
  /// 如果即将要运行的任务与队列中最后一个任务拥有相同的[taskKey]，也不会被抛弃，并且会更改
  /// 状态，如果两个key相等(==)会共享一个状态([_TaskIgnore])，由共享状态决定是否被抛弃,
  /// 每次任务调用开始时，会自动检查与最后一个任务是否拥有相同的[taskKey]，并更新状态。
  ///
  /// 无法抛弃正在运行中的任务。
  ///
  /// 返回的值可能为 null
  void addOneEventTask<T>(EventCallback<T> callback, {Object? taskKey}) =>
      _addEventTask<T?>(callback, onlyLastOne: true, taskKey: taskKey);

  /// 每一个实例提醒一次
  bool printOnce = false;

  Future<T> awaitTask<T>(EventCallback<T> callback, {Object? taskKey}) {
    if (doNotEnterQueue()) {
      assert(printOnce || (printOnce = true) && Log.e('note: 此次任务不会进入队列'));
      return Future.value(callback());
    }
    return _addEventTask(callback, taskKey: taskKey);
  }

  Future<T?> awaitOne<T>(EventCallback<T> callback, {Object? taskKey}) {
    if (doNotEnterQueue()) {
      assert(printOnce || (printOnce = true) && Log.e('note: 此次任务不会进入队列'));
      return Future.value(callback());
    }
    return _addEventTask(callback, onlyLastOne: true, taskKey: taskKey);
  }

  @pragma('vm:prefer-inline')
  bool doNotEnterQueue() {
    return _state == _ChannelState.one && _isCurrentQueueAndNotCompleted(this);
  }

  @pragma('vm:prefer-inline')
  static bool _isCurrentQueueAndNotCompleted(EventQueue currentQueue) {
    final localTask = currentTask;
    return localTask?._eventQueue == currentQueue && !localTask!._completed;
  }

  /// 自动选择要调用的函数
  late final EventRunCallback _runImpl = _getRunCallback();
  late final _ChannelState _state = _getState();
  EventRunCallback _getRunCallback() {
    switch (_state) {
      case _ChannelState.limited:
        return _limited;
      case _ChannelState.run:
        return _runAll;
      default:
        return eventRun;
    }
  }

  /// 与[channels]关系密切
  final _tasks = FutureAny();
  final _keyEvents = <Object, Set<_TaskEntry>>{};

  // 运行任务
  @pragma('vm:prefer-inline')
  Future<void> eventRun(_TaskEntry task) {
    return runZoned(task._run, zoneValues: {_zoneToken: task});
  }

  @pragma('vm:prefer-inline')
  Future<void> _limited(_TaskEntry task) async {
    _tasks.add(eventRun(task));

    // 达到 channels 数              ||  最后一个
    while (_tasks.length >= channels || _taskPool.isEmpty) {
      if (_tasks.isEmpty) break;
      await _tasks.any;
      await releaseUI;
    }
  }

  @pragma('vm:prefer-inline')
  Future<void> _runAll(_TaskEntry task) async {
    _tasks.add(eventRun(task));

    if (_taskPool.isEmpty) {
      while (_tasks.isNotEmpty) {
        if (_taskPool.isNotEmpty) break;
        await _tasks.any;
        await releaseUI;
      }
    }
  }

  void _start() {
    if (_active) return;
    _runner = _run();
  }

  /// 依赖于事件循环机制
  ///
  /// 执行任务队列
  Future<void> _run() async {
    _active = true;
    while (_taskPool.isNotEmpty) {
      await releaseUI;

      final task = _taskPool.removeFirst();
      //                      最后一个
      if (!task.onlyLastOne || _taskPool.isEmpty) {
        assert(task.notIgnoreOrNull || _taskPool.isEmpty);

        await _runImpl(task);
      } else {
        final taskKey = task.taskKey;
        if (taskKey != null) {
          assert(_keyEvents.containsKey(taskKey));
          final taskList = _keyEvents[taskKey]!;

          final last = _taskPool.last;

          final first = taskList.first;
          assert(first._taskIgnore != null);
          final ignore = last.taskKey != task.taskKey;
          first._ignore(ignore);
        }

        if (task.notIgnore) {
          await _runImpl(task);
          continue;
        }

        /// 任务被抛弃
        task._complete();
      }
    }
    _active = false;
  }
}

class _TaskEntry<T> {
  _TaskEntry({
    required this.callback,
    required EventQueue queue,
    this.taskKey,
    this.isOvserve = false,
    this.onlyLastOne = false,
  }) : _eventQueue = queue;

  final bool isOvserve;

  /// 此任务所在的事件队列
  final EventQueue _eventQueue;

  /// 具体的任务回调
  final EventCallback<T> callback;

  /// 可通过[EventQueue.currentTask]访问、修改；
  /// 作为数据、状态等
  dynamic value;

  final Object? taskKey;

  /// [onlyLastOne] == true 并且不是任务队列的最后一个任务，才会被抛弃
  /// 不管 [onlyLastOne] 为任何值，最后一个任务都会执行
  final bool onlyLastOne;

  bool get canDiscard => !_eventQueue.isLast && onlyLastOne;
  bool get ignore => _taskIgnore?.ignore == true;
  bool get notIgnoreOrNull => !ignore;

  bool get notIgnore => _taskIgnore?.ignore == false;
  void _ignore(bool v) {
    _taskIgnore?.ignore = v;
  }

  bool isCurrentQueue(EventQueue queue) {
    return _eventQueue == queue;
  }

  // 共享一个对象
  _TaskIgnore? _taskIgnore;

  final _outCompleter = Completer<T>();

  Future<T> get future => _outCompleter.future;

  // 队列循环要等待的对象
  Completer<void>? _innerCompleter;

  Future<void> _run() async {
    try {
      final result = callback();
      if (result is Future<T>) {
        assert(_innerCompleter == null);
        _innerCompleter ??= Completer<void>();
        result.then(_completeAll, onError: _completeErrorAll);
        return _innerCompleter!.future;
      }
      // 同步
      _complete(result);
    } catch (e) {
      _completedError(e);
    }
  }

  /// 从 [EventQueue.currentTask] 访问
  void addLast() {
    assert(!_completed);
    assert(EventQueue.currentTask != null);

    _innerComplete();
    _eventQueue
      .._taskPool.add(this)
      .._start();
  }

  bool _completed = false;

  /// [result] == null 的情况
  ///
  /// 1. [T] 为 void 类型
  /// 2. [onlyLastOne] == true 且被抛弃忽略
  @pragma('vm:prefer-inline')
  void _complete([T? result]) {
    if (_completed) return;

    _completed = true;
    _outCompleter.complete(result);
  }

  @pragma('vm:prefer-inline')
  void _completedError(Object error) {
    if (_completed) return;

    _completed = true;
    _outCompleter.completeError(error);
  }

  @pragma('vm:prefer-inline')
  void _innerComplete() {
    if (_innerCompleter != null) {
      assert(!_innerCompleter!.isCompleted);
      _innerCompleter!.complete();
      _innerCompleter = null;
    }
  }

  void _completeAll(T result) {
    if (_innerCompleter != null) {
      _innerComplete();
      _complete(result);
    }
  }

  void _completeErrorAll(Object error) {
    if (_innerCompleter != null) {
      _innerComplete();
      _completedError(error);
    }
  }
}

enum _ChannelState {
  /// 任务数量无限制
  run,

  /// 数量限制
  limited,

  /// 单任务
  one,
}

class _TaskIgnore {
  _TaskIgnore(this.ignore);

  bool ignore;
}

/// 进入 事件循环，
/// flutter engine 根据任务类型是否立即执行事件回调
/// 后续的任务会在恰当的时机运行，比如帧渲染优先等
// Future<void> get releaseUI => Future(_empty);
// void _empty() {}

Future<void> get releaseUI => release(Duration.zero);
Future<void> release(Duration time) => Future.delayed(time);

extension EventsPush<T> on FutureOr<T> Function() {
  void push(EventQueue events, {Object? taskKey}) {
    return events.addEventTask(this, taskKey: taskKey);
  }

  void pushOne(EventQueue events, {Object? taskKey}) {
    return events.addOneEventTask(this, taskKey: taskKey);
  }

  Future<T> pushAwait(EventQueue events, {Object? taskKey}) {
    return events.awaitTask(this, taskKey: taskKey);
  }

  Future<T?> pushOneAwait(EventQueue events, {Object? taskKey}) {
    return events.awaitOne(this, taskKey: taskKey);
  }
}
