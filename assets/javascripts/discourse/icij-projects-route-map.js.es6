export default function() {
  this.route("group", { path: "/g/:name", resetNamespace: true }, function() {
    this.route('categories');

    this.route("activity", function() {
      this.route("watching");
    })
  });
}
