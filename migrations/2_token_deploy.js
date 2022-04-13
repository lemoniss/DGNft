const dgnfToken = artifacts.require("DGNFToken");

module.exports = function (deployer) {
  deployer.deploy(dgnfToken);
  // deployer.deploy(bstToken);
}
