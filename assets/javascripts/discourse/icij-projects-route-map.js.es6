export default function() {
  this.route("group", { path: "/g/:name", resetNamespace: true }, function() {
    this.route('categories');
  });
}
