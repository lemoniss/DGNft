// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "./IERC165.sol";
import "./ERC165.sol";
import "./IERC721.sol";
import "../lib/SafeMath.sol";
import "../lib/Address.sol";
import "../lib/Counters.sol";
import "./IERC721Receiver.sol";

contract ERC721 is ERC165, IERC721 {
    using SafeMath for uint256;
    using Address for address;
    using Counters for Counters.Counter;

    // `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`와 동일
    // `IERC721Receiver(0).onERC721Received.selector`로부터 얻을 수도 있습니다
    bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;

    // 토큰 ID에서 소유자로의 매핑
    mapping (uint256 => address) internal _tokenOwner;

    // 토큰 ID에서 승인된 주소로의 매핑
    mapping (uint256 => address) private _tokenApprovals;

    // 소유자에서 소유한 토큰 개수로의 매핑
    mapping (address => Counters.Counter) private _ownedTokensCount;

    // 소유자에서 운영자(operator) 승인 여부로의 매핑
    mapping (address => mapping (address => bool)) private _operatorApprovals;

    // Array with all token ids, used for enumeration (custom)
    uint256[] internal _allTokens;

    /*
     *     bytes4(keccak256('balanceOf(address)')) == 0x70a08231
     *     bytes4(keccak256('ownerOf(uint256)')) == 0x6352211e
     *     bytes4(keccak256('approve(address,uint256)')) == 0x095ea7b3
     *     bytes4(keccak256('getApproved(uint256)')) == 0x081812fc
     *     bytes4(keccak256('setApprovalForAll(address,bool)')) == 0xa22cb465
     *     bytes4(keccak256('isApprovedForAll(address,address)')) == 0xe985e9c
     *     bytes4(keccak256('transferFrom(address,address,uint256)')) == 0x23b872dd
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256)')) == 0x42842e0e
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256,bytes)')) == 0xb88d4fde
     *
     *     => 0x70a08231 ^ 0x6352211e ^ 0x095ea7b3 ^ 0x081812fc ^
     *        0xa22cb465 ^ 0xe985e9c ^ 0x23b872dd ^ 0x42842e0e ^ 0xb88d4fde == 0x80ac58cd
     */
    bytes4 private constant _INTERFACE_ID_ERC721 = 0x80ac58cd;

    constructor() public {
        // ERC165를 통해 ERC721을 준수하도록 지원되는 인터페이스를 등록하세요
        _registerInterface(_INTERFACE_ID_ERC721);
    }

    /**
     * @dev 명시한 주소의 잔액을 얻습니다.
     * @param owner 잔액을 요청하는 주소
     * @return uint256 전달받은 주소가 보유한 수량
     */
    function balanceOf(address owner) public view returns (uint256) {
        require(owner != address(0), "ERC721: balance query for the zero address");

        return _ownedTokensCount[owner].current();
    }

    /**
     * @dev 명시된 토큰 ID의 소유자를 얻습니다.
     * @param tokenId uint256 소유자를 요청하는 토큰의 ID
     * @return address 주어진 토큰 ID의 현재 표시된 소유자
     */
    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _tokenOwner[tokenId];
        require(owner != address(0), "ERC721: owner query for nonexistent token");

        return owner;
    }

    /**
     * @dev 주어진 토큰 ID의 전송을 다른 주소에게 허가합니다.
     * 영(zero) 주소는 승인된 주소가 없음을 나타냅니다.
     * 한 번에 하나의 승인된 주소만 있을 수 있습니다.
     * 토큰 소유자나 승인된 운영자만이 호출할 수 있습니다.
     * @param to address 주어진 토큰 ID에 대해 승인할 주소
     * @param tokenId uint256 승인하고자 하는 토큰 ID
     */
    function approve(address to, uint256 tokenId) public {
        address owner = ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(msg.sender == owner || isApprovedForAll(owner, msg.sender),
            "ERC721: approve caller is not owner nor approved for all"
        );

        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    /**
     * @dev 토큰 ID에 대해 승인된 주소를, 만일 설정된 주소가 없으면 0을 얻습니다.
     * 만일 토큰 ID가 존재하지 않는 경우 되돌려집니다.
     * @param tokenId uint256 승인된 주소를 요청하는 토큰의 ID
     * @return address 주어진 토큰 ID에 대해 현재 승인된 주소
     */
    function getApproved(uint256 tokenId) public view returns (address) {
        require(_exists(tokenId), "ERC721: approved query for nonexistent token");

        return _tokenApprovals[tokenId];
    }

    /**
     * @dev 주어진 운영자의 승인을 설정 또는 해제합니다.
     * 운영자는 발신자를 대신해 모든 토큰을 전송할 수 있도록 허가되었습니다.
     * @param to 승인을 설정하고자 하는 운영자의 주소
     * @param approved 설정하고자 하는 승인의 상태를 나타냅니다
     */
    function setApprovalForAll(address to, bool approved) public {
        require(to != msg.sender, "ERC721: approve to caller");

        _operatorApprovals[msg.sender][to] = approved;
        emit ApprovalForAll(msg.sender, to, approved);
    }

    /**
     * @dev 주어진 소유자에 대해 운영자가 승인되었는지 여부를 말해줍니다.
     * @param owner 승인을 조회하고자 하는 소유자 주소
     * @param operator 승인을 조회하고자 하는 운영자 주소
     * @return bool 주어진 운영자가 주어진 소유자로부터 승인되었는지 여부
     */
    function isApprovedForAll(address owner, address operator) public view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    /**
     * @dev 주어진 토큰 ID의 소유권을 다른 주소로 전송합니다.
     * 이 메소드는 사용하지 않는 것이 좋습니다. 가능하다면 `safeTransferFrom`을 사용하세요.
     * msg.sender는 소유자, 승인된 주소, 또는 운영자여야 합니다.
     * @param from 토큰의 현재 소유자
     * @param to 주어진 토큰 ID의 소유권을 받을 주소
     * @param tokenId 전송할 토큰의 uint256 ID
     */
    function transferFrom(address from, address to, uint256 tokenId) public {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(msg.sender, tokenId), "ERC721: transfer caller is not owner nor approved");

        _transferFrom(from, to, tokenId);
    }

    /**
     * @dev 주어진 토큰 ID의 소유권을 다른 주소로 안전하게 전송합니다.
     * 만일 목표 주소가 컨트랙트라면, 컨트랙트는 `onERC721Received`를 구현했어야만 합니다.
     * 이는 안전한 전송으로부터 호출되며 마법의 값
     * `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`를 반환합니다;
     * 만일 다른 경우에는 전송이 되돌려집니다.
     * msg.sender는 소유자, 승인된 주소, 운영자여야 합니다
     * @param from 토큰의 현재 소유자
     * @param to 주어진 토큰 ID의 소유권을 받을 주소
     * @param tokenId 전송할 토큰의 uint256 ID
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) public {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev 주어진 토큰 ID의 소유권을 다른 주소로 안전하게 전송합니다.
     * 만일 목표 주소가 컨트랙트라면, 컨트랙트는 `onERC721Received`를 구현했어야만 합니다.
     * 이는 안전한 전송으로부터 호출되며 마법의 값
     * `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`를 반환합니다;
     * 만일 다른 경우에는 전송이 되돌려집니다.
     * msg.sender는 소유자, 승인된 주소, 운영자여야 합니다
     * @param from 토큰의 현재 소유자
     * @param to 주어진 토큰 ID의 소유권을 받을 주소
     * @param tokenId 전송할 토큰의 uint256 ID
     * @param _data 안전한 전송 검사와 함께 전송하고자 하는 바이트 데이터
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public {
        transferFrom(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    /**
     * @dev 지정한 토큰이 존재하는지 여부를 반환합니다.
     * @param tokenId uint256 존재를 조회하고자 하는 토큰의 ID
     * @return bool 토큰의 존재 여부
     */
    function _exists(uint256 tokenId) internal view returns (bool) {
        address owner = _tokenOwner[tokenId];
        return owner != address(0);
    }

    /**
     * @dev 지정된 납부자가 주어진 토큰 ID를 전송할 수 있는지 여부를 반환합니다.
     * @param spender 조회하고자 하는 납부자의 주소
     * @param tokenId uint256 전송하고자 하는 토큰 ID
     * @return bool msg.sender가 주어진 토큰 ID에 대해 승인되었는지,
     * 운영자인지, 또는 토큰의 소유자인지 여부
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        require(_exists(tokenId), "ERC721: operator query for nonexistent token");
        address owner = ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    /**
     * @dev 새 토큰을 발행하기 위한 내부 함수.
     * 주어진 토큰 ID가 이미 존재하면 되돌립니다.
     * @param to 발행된 토큰을 소유할 주소
     * @param tokenId uint256 발행될 토큰의 ID
     */
    function _mint(address to, uint256 tokenId) internal {
        require(to != address(0), "ERC721: mint to the zero address");
        require(!_exists(tokenId), "ERC721: tokenId is already minted");

        _tokenOwner[tokenId] = to;
        _ownedTokensCount[to].increment();

        // _allTokens 에도 push 해야함 (custom)
        _allTokens.push(tokenId);

        emit Transfer(address(0), to, tokenId);
    }

    /**
     * @dev 특정 토큰을 소각하기 위한 내부 함수.
     * 토큰이 존재하지 않으면 되돌립니다.
     * 더 이상 사용되지 않으며, _burn(uint256)을 대신 사용하세요.
     * @param owner 소각할 토큰의 소유자
     * @param tokenId uint256 소각할 토큰의 ID
     */
    function _burn(address owner, uint256 tokenId) internal {
        require(ownerOf(tokenId) == owner, "ERC721: burn of token that is not own");

        _clearApproval(tokenId);

        _ownedTokensCount[owner].decrement();
        _tokenOwner[tokenId] = address(0);

        // _allTokens 삭제
        _allTokens[tokenId] = _allTokens.length - 1;
        _allTokens.pop();

        emit Transfer(owner, address(0), tokenId);
    }

    /**
     * @dev 특정 토큰을 소각하기 위한 내부 함수.
     * 토큰이 존재하지 않으면 되돌립니다.
     * @param tokenId uint256 소각할 토큰의 ID
     */
    function _burn(uint256 tokenId) internal {
        _burn(ownerOf(tokenId), tokenId);
    }

    /**
     * @dev 주어진 토큰 ID의 소유권을 다른 주소로 전송하기 위한 내부 함수.
     * transferFrom과 달리, msg.sender에 제한이 없습니다.
     * @param from 토큰의 현재 소유자
     * @param to 주어진 토큰 ID의 소유권을 받고자 하는 주소
     * @param tokenId uint256 전송될 토큰의 ID
     */
    function _transferFrom(address from, address to, uint256 tokenId) internal {
        require(ownerOf(tokenId) == from, "ERC721: transfer of token that is not own");
        require(to != address(0), "ERC721: transfer to the zero address");

        _clearApproval(tokenId);

        _ownedTokensCount[from].decrement();
        _ownedTokensCount[to].increment();

        _tokenOwner[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    /**
     * @dev Internal function to invoke `onERC721Received` on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * This function is deprecated.
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param _data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory _data) internal returns (bool) {
        if (!to.isContract()) {
            return true;
        }

        bytes4 retval = IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, _data);
        return (retval == _ERC721_RECEIVED);
    }

    /**
     * @dev 주어진 토큰 ID의 현재 승인을 지우는 개인 함수.
     * @param tokenId uint256 전송할 토큰의 ID
     */
    function _clearApproval(uint256 tokenId) private {
        if (_tokenApprovals[tokenId] != address(0)) {
            _tokenApprovals[tokenId] = address(0);
        }
    }
}