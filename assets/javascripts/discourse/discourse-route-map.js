export default function () {
  this.route("my-escrows", { path: "/my-escrows" });
  this.route("escrow-offer", { path: "/escrow-offer/:id" });
}
