//
//  UserController+authenticate.swift
//  ExpressWash
//
//  Created by Joel Groomer on 5/11/20.
//  Copyright © 2020 Bobby Keffury. All rights reserved.
//

import Foundation
import CoreData
import UIKit

extension UserController {
    var bearerToken: String { "Bearer \(token ?? "")" }

    func authenticate(username: String,
                      password: String,
                      completion: @escaping (User?, Error?) -> Void) {
        guard !username.isEmpty && !password.isEmpty else {
            completion(nil, NSError(domain: "auth", code: INVALIDUSERNAMEORPASSWORD, userInfo: nil))
            return
        }

        let authURL = BASEURL.appendingPathComponent(ENDPOINTS.login.rawValue)
        var request = URLRequest(url: authURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let postBody = PostBody(email: username, password: password)

        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(postBody)
            request.httpBody = data
        } catch {
            completion(nil, error)
            return
        }

        SESSION.dataTask(with: request) { (data, response, error) in
            if let error = error {
                print("Error when trying to sign in: \(error)")
                completion(nil, error)
                return
            }
            if let response = response as? HTTPURLResponse {
                if response.statusCode == 403 {
                    completion(nil, NSError(domain: "auth-response",
                                                 code: INVALIDUSERNAMEORPASSWORD,
                                                 userInfo: nil))
                    return
                } else if response.statusCode != 200 {
                    completion(nil, NSError(domain: "auth-response", code: response.statusCode, userInfo: nil))
                    return
                }
            }

            guard let data = data else {
                completion(nil, NSError(domain: "auth-response", code: NODATAERROR, userInfo: nil))
                return
            }
            let decoder = JSONDecoder()
            do {
                let authReturn = try decoder.decode(AuthReturn.self, from: data)
                self.token = authReturn.token
                self.sessionUser = self.findUser(byID: authReturn.user.userId)
                if self.sessionUser != nil {
                    self.update(user: self.sessionUser!, with: authReturn.user)
                } else {
                    self.sessionUser = User(representation: authReturn.user)
                }
                completion(self.sessionUser, nil)
            } catch {
                completion(nil, error)
                return
            }
        }.resume()
    }

    struct PostBody: Encodable {
        var email: String
        var password: String
    }

    struct AuthReturn: Decodable {
        var token: String
        var user: UserRepresentation
    }

    func validateToken(completion: @escaping (Bool) -> Void) {
        guard token != nil else {
            completion(false)
            return
        }
        let requestURL = BASEURL.appendingPathComponent(ENDPOINTS.users.rawValue)
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue(bearerToken, forHTTPHeaderField: "Authorization")
        SESSION.dataTask(with: request) { (_, response, error) in
            if error != nil {
                completion(false)
                return
            }

            if let response = response as? HTTPURLResponse {
                if response.statusCode == 200 {
                    completion(true)
                    return
                }
            }
            completion(false)
        }
    }

    func reAuthenticate(sender: UIViewController,
                        completion: @escaping (Error?) -> Void) {

        // if the user has saved their password
        if let password = password, let email = sessionUser?.email {

            authenticate(username: email, password: password) { (_, error) in
                if error != nil {
                    completion(error)
                    return
                }
                completion(nil)
            }
        }

        // if the user did not save their password...

        //create an alert asking for their email and password
        let alert = UIAlertController(title: "Session expired", message: "Please sign in again", preferredStyle: .alert)
        alert.addTextField { txt in
            txt.placeholder = "email"
        }
        alert.addTextField { txt in
            txt.placeholder = "password"
        }

        // if they tap OK, try to sign in
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            if let email = alert.textFields?[0].text,
                let password = alert.textFields?[1].text {
                self.authenticate(username: email,
                                  password: password) { (user, error) in
                    if error != nil {
                        completion(error)
                        return
                    }
                    completion(nil)
                }
            } else {
                self.reAuthenticate(sender: sender, completion: completion)
            }
        }))

        // if they tap cancel, sign them out
        alert.addAction(UIAlertAction(title: "Cancel", style: .destructive, handler: { _ in
            self.token = nil
            self.sessionUser = nil
            completion(NSError(domain: "re-authenticate", code: CANCELLED, userInfo: nil))
            sender.dismiss(animated: true, completion: nil)
        }))

        sender.present(alert, animated: true, completion: nil)
    }
}