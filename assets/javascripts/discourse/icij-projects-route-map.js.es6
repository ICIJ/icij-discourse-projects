export default function() {
  this.route('group', { path: '/groups/:name', resetNamespace: true }, function() {
    this.route('categories');
  });

  this.route('group', { path: '/groups/:name', resetNamespace: true }, function() {
    this.route('topics');
  });
}
