class FpsCounter {
  int _frames = 0;
  DateTime _last = DateTime.now();
  double fps = 0;
  void tick() {
    _frames++;
    final now = DateTime.now();
    final dt = now.difference(_last).inMilliseconds;
    if (dt >= 500) {
      fps = (_frames * 1000) / dt;
      _frames = 0;
      _last = now;
    }
  }
}