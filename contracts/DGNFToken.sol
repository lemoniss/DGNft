// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;
pragma experimental ABIEncoderV2;

import "./token/ERC721.sol";

contract BSNFToken is ERC721 {

    struct Metadata {
        string  title;  // 토큰제목
        string  imageUrl;  // 토큰이미지URL
        uint256 regDt;  // 토큰생성시간
    }

    Metadata[] public metadatas; // default: []
    address public owner;          // 컨트랙트 소유자

    constructor() public {
        owner = msg.sender;
    }

    modifier isOwner() {
        require(owner == msg.sender, "관리자만 사용할 수 있습니다.");
        _;
    }

    // 생성
    function createNft(string memory title, string memory imageUrl, address account) public isOwner {

        uint256 tokenId = metadatas.length; // 유일한 Metadata ID (metadatas 배열 인덱스)
        metadatas.push(Metadata(title, imageUrl, now));
        super._mint(account, tokenId); // ERC721 발행
    }

    // 내 주소의 모든 NFT토큰 가져오기 (custom)
    function getMyNftTokenIds() external view returns(uint256[] memory ownerTokens) {

        uint256 tokenCount = super.balanceOf(msg.sender);

        if (tokenCount == 0) {
            // Return an empty array
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 resultIndex = 0;

            for (uint256 i= 0; i< _allTokens.length; i++) {
                if (_tokenOwner[i] == msg.sender) {
                    result[resultIndex] = i;
                    resultIndex++;
                }
            }

            return result;
        }
    }

    function getMyNftMetadata(uint256 tokenId) external view returns(Metadata memory meta) {
        return metadatas[tokenId];
    }
}