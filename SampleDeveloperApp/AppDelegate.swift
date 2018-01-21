//
//  AppDelegate.swift
//  SampleDeveloperApp
//
//  Created by Marissa Le Coz on 9/23/17.
//  Copyright © 2017 Marissa Le Coz. All rights reserved.
//

import UIKit
import CloudKit
import UserNotifications
import Firebase
import FirebaseDatabase
import FirebaseAuth
import PromiseKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    var window: UIWindow?
    
    let db = CKContainer(identifier: "iCloud.com.MarissaLeCozz.SampleDeveloperApp").publicCloudDatabase
    
    var firebaseDBRef: DatabaseReference?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        FirebaseApp.configure()
        firebaseDBRef = Database.database().reference()
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }

    // This function is called when another app on the device opens the URL for this app.
    func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any] = [:]) -> Bool {
        
        // which app opened you
        guard let sendingAppID = options[.sourceApplication] as? String else {
            return false
        }
        
        if sendingAppID == "com.MarissaLeCoz.AnalyticsApp" {
            logIn()
        }
        
        return true
    }
    
    func logIn() {
        
        let popUp = UIAlertController(title: "CKTrends Login", message: "Please use your CKTrends username and password to log in and refresh your trend tracking!", preferredStyle: UIAlertControllerStyle.alert)
        popUp.addTextField() { emailField in
            emailField.placeholder = "email"
        }
        popUp.addTextField() { passwordField in
            passwordField.placeholder = "password"
            passwordField.isSecureTextEntry = true
        }
        
        popUp.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.default, handler: nil))
        popUp.addAction(UIAlertAction(title: "Login", style: UIAlertActionStyle.default) { alert in
            
            guard let email = popUp.textFields![0].text, let password = popUp.textFields![1].text else {
                return
            }

            Auth.auth().signIn(withEmail: email, password: password) { (user, error) in
                if (error != nil) {
                    guard let vc = self.window?.rootViewController else {
                        return
                    }
                    CKTrendsUtilities.presentAlert(title: "Uh Oh!", message: "Sign in failed. Please check your email and password. Tap the Refresh button in CKTrends to try again.", vc: vc)
                }
                else {
                    guard let uid = user?.uid else {
                        return
                    }
                    self.updateCKTrends(uid: uid)
                }
            }
        })
        

        self.window?.rootViewController?.present(popUp, animated: true, completion: nil)
        
    }
    
    func updateCKTrends(uid: String) {
        
        let appID = 1
        let recordTypesToTrack = ["RecordTypeA"] // add B later
        //var success = 1 // means everything is good
        
        Database.database().reference().child("users").child("\(uid)").child("\(appID)").setValue(["STATE": "in_progress"], withCompletionBlock: { (error, ref) in
            
            if error == nil {
                
                let group = DispatchGroup()
                
                for recordType in recordTypesToTrack {
                    
                    group.enter()
                    
                    // check to see whether the user has tracked this app before; if not, add it to tracking list
                    let pathString = "users/\(uid)/\(appID)/TRACKING"
                    Database.database().reference().child(pathString).observeSingleEvent(of: .value) { snapshot, error in
                        
                        if error != nil {
                            Database.database().reference().child("users").child("\(uid)").child("\(appID)").setValue(["STATE": "failed"], withCompletionBlock: { (error, ref) in
                                if error != nil {
                                    //success = 0
                                    group.leave()
                                }
                            })
                        }
                            
                        else {
                            
                            var isNewRecordType = false
                            
                            let recordTypeDict = snapshot.value as? [String:Any]?
                            if recordTypeDict == nil || recordTypeDict!?[recordType] == nil {
                                isNewRecordType = true
                            }
                            
                            // add to tracking (even if already there). It's just easier in terms of asynchronicity
                            Database.database().reference().child("users").child("\(uid)").child("\(appID)").child("TRACKING").setValue([recordType: "true"], withCompletionBlock: { (error, ref) in

                                if error == nil {
                                    
                                    // if this is a new record type, query all records of this type
                                    if isNewRecordType {
                                        
                                        let predicate = NSPredicate(value: true)
                                        let query = CKQuery(recordType: recordType, predicate: predicate)
                                        
                                        self.db.perform(query, inZoneWith: nil) { records, error in
                                            
                                            if error == nil {
                                                
                                                guard let records = records else {
                                                    return
                                                }
                                                self.saveRecordCounts(records: records, uid: uid, appID: appID, recordType: recordType, group: group)
         
                                            }
                                            else {
                                                Database.database().reference().child("users/\(uid)").child("\(appID)").setValue(["STATE": "failed"], withCompletionBlock: { (error, ref) in
                                                    if error != nil {
                                                        //success = 0
                                                        group.leave()
                                                    }
                                                })
                                            }
                                        }
                                    }
                                        
                                    // if this isn't a new record type, query all record since the last time this type was tracked
                                    else {
                                        
                                        let lastCheckPath = "users/\(uid)/\(appID)/LAST_CHECK/\(recordType)"
                                        Database.database().reference().child(lastCheckPath).observeSingleEvent(of: .value) { snapshot, error in
                                            if error != nil {
                                                Database.database().reference().child("users").child("\(uid)").child("\(appID)").setValue(["STATE": "failed"], withCompletionBlock: { (error, ref) in
                                                    if error != nil {
                                                        //success = 0
                                                        group.leave()
                                                    }
                                                })
                                            }
                                            // get the last time this record type was checked and query for everything that day/time and after.
                                            else {
                                                
                                                let recordTypeToLastCheckDict = snapshot.value as? [String:Any]?
                                                guard let lastCheck = recordTypeToLastCheckDict!?[recordType] as? Date else {
                                                    return
                                                }
                                                
                                                let predicate = NSPredicate(format: "%K > %@", "creationDate", lastCheck as CVarArg) // TODO does this work???
                                                let query = CKQuery(recordType: recordType, predicate: predicate)
                                                
                                                self.db.perform(query, inZoneWith: nil) { records, error in
                                                    
                                                    if error == nil {
                                                        
                                                        guard let records = records else {
                                                            return
                                                        }
                                                        
                                                        self.saveRecordCounts(records: records, uid: uid, appID: appID, recordType: recordType, group: group)

                                                    }
                                                    else {
                                                        Database.database().reference().child("users").child("\(uid)").child("\(appID)").setValue(["STATE": "failed"], withCompletionBlock: { (error, ref) in
                                                            if error != nil {
                                                                //success = 0
                                                                group.leave()
                                                            }
                                                        })
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            })
                        }
                    }
                }
                group.notify(queue: .global(), execute: {
                    Database.database().reference().child("users").child("\(uid)").child("\(appID)").setValue(["STATE": "succeeded"])
                })
            }
            else {
                // ??
            }
        })
    }

    
    func saveRecordCounts(records: [CKRecord], uid: String, appID: Int, recordType: String, group: DispatchGroup) {

        var dateToCountDict = [String:Int]()
        
        for record in records {
            guard let date = record["creationDate"] as? Date else {
                return
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd-yy"
            let formattedDate = formatter.string(from: date)
            
            if dateToCountDict[formattedDate] != nil {
                dateToCountDict[formattedDate] = dateToCountDict[formattedDate]! + 1
            }
            else {
                dateToCountDict[formattedDate] = 1
            }
        }
        
        // now the dictionary is populated; add to firebase db
        for (date, count) in dateToCountDict {
            Database.database().reference().child("users").child("\(uid)").child("\(appID)").child("\(date)").setValue([recordType: "\(count)"], withCompletionBlock: { (error, ref) in
                if error == nil {
                    // record LAST_CHECK
                    let date = Date()
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
                    let formattedDate = formatter.string(from: date)
                    Database.database().reference().child("users").child("\(uid)").child("\(appID)").setValue(["LAST_CHECK": formattedDate], withCompletionBlock: { (error, ref) in
                        if error != nil {
                            //success = 0
                            group.leave()
                        }
                        else {
                            group.leave()
                        }
                    }) // today // TODO does this work????
                }
                else {
                    Database.database().reference().child("users").child("\(uid)").child("\(appID)").setValue(["STATE": "failed"], withCompletionBlock: { (error, ref) in
                        if error != nil {
                            //success = 0
                            group.leave()
                        }
                    })
                }
            })
        }
    }
}

//let path = "users/\(uid)/\(appID)/\(formattedDate)"
//Database.database().reference().child(path).observeSingleEvent(of: .value) { snapshot, error in
//    var newCount: Int
//    let recordTypeToCountDict = snapshot.value as? [String:Any]? // record type : number
//    if recordTypeToCountDict == nil || recordTypeToCountDict!?[recordType] == nil {
//        newCount = 1
//    }
//    else {
//        guard let oldCount = (recordTypeToCountDict!?[recordType] as? NSString)?.integerValue else {
//            return
//        }
//        newCount = oldCount + 1
//
//    }
//    Database.database().reference().child("users").child("\(uid)").child("\(appID)").child("\(formattedDate)").setValue([recordType: "\(newCount)"])
//
//}

