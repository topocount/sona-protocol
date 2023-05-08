pragma solidity ^0.8.16;

import { SonaAdmin } from "../../access/SonaAdmin.sol";
import { Util } from "../Util.sol";

contract SonaAdminTest is Util, SonaAdmin {
	function test_isSonaAdmin() public view {
		isSonaAdmin(msg.sender);
	}

	function testFail_notAllowedToGrantAdmin() public {
		grantRole(_ADMIN_ROLE, msg.sender);
	}

	function testFail_notAllowedToRevokeAdmin() public {
		revokeRole(_ADMIN_ROLE, msg.sender);
	}
}
