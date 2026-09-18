/// All route paths in one place so screens never hard-code navigation
/// strings inline.
class RoutePaths {
  const RoutePaths._();

  static const String splash = '/splash';
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';

  static const String home = '/home';
  static const String create = '/create';
  static const String createImage = '/create/image';
  static const String createMusic = '/create/music';
  static const String createVideo = '/create/video';
  static const String createFunnel = '/create/funnel';
  static const String history = '/history';
  static const String projects = '/projects';
  static const String profile = '/profile';

  static const String settings = '/settings';
  static const String notifications = '/notifications';
  static const String plans = '/plans';
  static const String usageDashboard = '/usage';
  static const String creditHistory = '/credits/history';

  static String generationDetail(String id) => '/history/$id';
  static String projectDetail(String id) => '/projects/$id';
  static String funnelEditor(String id) => '/funnels/$id/edit';
  static String funnelPreview(String id) => '/funnels/$id/preview';
}
