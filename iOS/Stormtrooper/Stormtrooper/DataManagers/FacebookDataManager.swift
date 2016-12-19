//
//  FacebookDataManager.swift
//  Stormtrooper
//
//  Created by Daniel Firsht on 12/9/16.
//  Copyright © 2016 IBM. All rights reserved.
//

import Foundation
import FBSDKLoginKit

class FacebookDataManager {
	static let sharedInstance = FacebookDataManager()
	
	var profile: FBSDKProfile? {
		return FBSDKProfile.current() ?? nil
	 }
	
	private let urlSession = URLSession.shared
	private let accountDataManager = AccountDataManager.sharedInstance
	private let csyncDataManager = CSyncDataManager.sharedInstance
	
	func setupLoginButton(_ button: FBSDKLoginButton) {
		button.readPermissions = ["public_profile", "email", "user_friends"]
	}
	
	func fetchFriends(callback: @escaping (Error?, [User]?) -> Void) {
		innerFetchFriends(withAfterCursor: nil, friends: [], callback: callback)
	}
	
	func fetchProfilePictureForCurrentUser(as size: CGSize, callback: @escaping (Error?, UIImage?) -> Void) {
		guard let profile = profile, let pictureURL = profile.imageURL(for: .square, size: size) else {
			callback(ServerError.invalidConfiguration, nil)
			return
		}
		
		let task = urlSession.dataTask(with: pictureURL){data, response, error in
			guard error == nil else {
				callback(error, nil)
				return
			}
			guard let data = data, let picture = UIImage(data: data) else {
				callback(ServerError.unexpectedResponse, nil)
				return
			}
			callback(nil, picture)
		}
		task.resume()
	}
	
	func fetchInfoForUser(withID id: String, callback: @escaping (Error?, User?) -> Void) {
		let parameters = ["fields": "name, picture"]
		let request = FBSDKGraphRequest(graphPath: id, parameters: parameters)
		let _ = request?.start(){ (request, result, error) in
			guard error == nil else {
				callback(error, nil)
				return
			}
			guard let result = result as? [String: Any] else {
				callback(ServerError.unexpectedResponse, nil)
				return
			}
			let user = User(facebookResponse: result)
			callback(nil, user)
		}
	}
	
	private init() {
		NotificationCenter.default.addObserver(self, selector: #selector(accessTokenDidChange), name: NSNotification.Name.FBSDKAccessTokenDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(profileDidChange), name: NSNotification.Name.FBSDKProfileDidChange, object: nil)
		
		if let profile = profile {
			csyncDataManager.authenticate(withID: profile.userID)
		}
	}
	
	
	@objc private func accessTokenDidChange(notification: Notification) {
		if let accessToken = FBSDKAccessToken.current() {
			accountDataManager.signup(withFacebookAccessToken: accessToken.tokenString)
		}
	}
	
	@objc private func profileDidChange(notification: Notification) {
		if let profile = profile {
			csyncDataManager.authenticate(withID: profile.userID)
		}
	}
	
	deinit {
		NotificationCenter.default.removeObserver(self)
	}
	
	private func innerFetchFriends(withAfterCursor afterCursor: String?, friends: [User], callback: @escaping (Error?, [User]?) -> Void) {
		var afterCursor = afterCursor
		var friends = friends
		var parameters = ["fields": "friends{name, picture}"]
		if let afterCursor = afterCursor {
			parameters["after"] = afterCursor
		}
		let request = FBSDKGraphRequest(graphPath: "me", parameters: parameters)
		let _ = request?.start(){ (request, result, error) in
			if error != nil {
				callback(error,nil)
			}
			else {
				let friendsResult = (result as? [String: Any])?["friends"] as? [String: Any]
				guard let friendsPage = friendsResult?["data"] as? [[String: Any]] else {
					return
				}
				for friend in friendsPage {
					friends.append(User(facebookResponse: friend))
				}
				let paging = friendsResult?["paging"] as? [String: Any]
				if paging?["next"] != nil {
					let cursors = paging?["cursors"] as? [String: String]
					afterCursor = cursors?["after"]
				}
				if afterCursor != nil {
					self.innerFetchFriends(withAfterCursor: afterCursor, friends: friends, callback: callback)
				}
				else {
					callback(nil, friends)
				}
			}
		}
	}
}