//
//  SearchContactsViewController.swift
//  Yep
//
//  Created by NIX on 16/3/21.
//  Copyright © 2016年 Catch Inc. All rights reserved.
//

import UIKit
import RealmSwift
import KeyboardMan

class SearchContactsViewController: SegueViewController {

    var originalNavigationControllerDelegate: UINavigationControllerDelegate?
    private var contactsSearchTransition: ContactsSearchTransition?

    @IBOutlet weak var searchBar: UISearchBar! {
        didSet {
            searchBar.placeholder = NSLocalizedString("Search Friend", comment: "")
        }
    }
    @IBOutlet weak var searchBarBottomLineView: HorizontalLineView! {
        didSet {
            searchBarBottomLineView.lineColor = UIColor(white: 0.68, alpha: 1.0)
        }
    }
    @IBOutlet weak var searchBarTopConstraint: NSLayoutConstraint!

    private let headerIdentifier = "TableSectionTitleView"
    private let searchSectionTitleCellID = "SearchSectionTitleCell"
    private let searchedUserCellID = "SearchedUserCell"
    private let searchedDiscoveredUserCellID = "SearchedDiscoveredUserCell"

    @IBOutlet weak var contactsTableView: UITableView! {
        didSet {
            contactsTableView.separatorColor = UIColor.yepCellSeparatorColor()
            contactsTableView.separatorInset = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 0)

            contactsTableView.registerClass(TableSectionTitleView.self, forHeaderFooterViewReuseIdentifier: headerIdentifier)
            contactsTableView.registerNib(UINib(nibName: searchSectionTitleCellID, bundle: nil), forCellReuseIdentifier: searchSectionTitleCellID)
            contactsTableView.registerNib(UINib(nibName: searchedUserCellID, bundle: nil), forCellReuseIdentifier: searchedUserCellID)
            contactsTableView.registerNib(UINib(nibName: searchedDiscoveredUserCellID, bundle: nil), forCellReuseIdentifier: searchedDiscoveredUserCellID)

            contactsTableView.sectionHeaderHeight = 0
            contactsTableView.sectionFooterHeight = 0
            contactsTableView.contentInset = UIEdgeInsets(top: -30, left: 0, bottom: 0, right: 0)

            contactsTableView.tableFooterView = UIView()
        }
    }

    private let keyboardMan = KeyboardMan()

    private lazy var friends = normalFriends()
    private var filteredFriends: Results<User>?

    private var searchedUsers = [DiscoveredUser]()

    private var countOfFilteredFriends: Int {
        return filteredFriends?.count ?? 0
    }
    private var countOfSearchedUsers: Int {
        return searchedUsers.count
    }

    private var keyword: String?

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("Search", comment: "") 

        keyboardMan.animateWhenKeyboardAppear = { [weak self] _, keyboardHeight, _ in
            self?.contactsTableView.contentInset.bottom = keyboardHeight
            self?.contactsTableView.scrollIndicatorInsets.bottom = keyboardHeight
        }

        keyboardMan.animateWhenKeyboardDisappear = { [weak self] _ in
            self?.contactsTableView.contentInset.bottom = 0
            self?.contactsTableView.scrollIndicatorInsets.bottom = 0
        }

        searchBarBottomLineView.hidden = true
    }

    private var isFirstAppear = true
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.setNavigationBarHidden(true, animated: true)
    }

    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)

        if let delegate = contactsSearchTransition {
            navigationController?.delegate = delegate
        }

        UIView.animateWithDuration(0.25, delay: 0.0, options: .CurveEaseInOut, animations: { [weak self] _ in
            self?.searchBarTopConstraint.constant = 0
            self?.view.layoutIfNeeded()
        }, completion: nil)

        if isFirstAppear {
            searchBar.becomeFirstResponder()
        }

        isFirstAppear = false
    }

    // MARK: Private

    private func updateContactsTableView(scrollsToTop scrollsToTop: Bool = false) {
        dispatch_async(dispatch_get_main_queue()) { [weak self] in
            self?.contactsTableView.reloadData()

            if scrollsToTop {
                self?.contactsTableView.yep_scrollsToTop()
            }
        }
    }

    private func hideKeyboard() {

        searchBar.resignFirstResponder()
        searchBar.yep_enableCancelButton()
    }

    // MARK: - Navigation

    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {

        guard let identifier = segue.identifier else {
            return
        }

        switch identifier {

        case "showProfile":
            let vc = segue.destinationViewController as! ProfileViewController

            if let user = sender as? User {
                if user.userID != YepUserDefaults.userID.value {
                    vc.profileUser = .UserType(user)
                }

            } else if let discoveredUser = (sender as? Box<DiscoveredUser>)?.value {
                vc.profileUser = .DiscoveredUserType(discoveredUser)
            }

            vc.hidesBottomBarWhenPushed = true
            
            vc.setBackButtonWithTitle()

            // 记录原始的 contactsSearchTransition 以便 pop 后恢复
            contactsSearchTransition = navigationController?.delegate as? ContactsSearchTransition

            navigationController?.delegate = originalNavigationControllerDelegate

        default:
            break
        }
    }
}

// MARK: - UISearchBarDelegate

extension SearchContactsViewController: UISearchBarDelegate {

    func searchBarShouldBeginEditing(searchBar: UISearchBar) -> Bool {

        searchBarBottomLineView.hidden = false

        return true
    }

    func searchBarCancelButtonClicked(searchBar: UISearchBar) {

        searchBar.text = nil
        searchBar.resignFirstResponder()

        searchBarBottomLineView.hidden = true

        (tabBarController as? YepTabBarController)?.setTabBarHidden(false, animated: true)

        navigationController?.popViewControllerAnimated(true)
    }

    func searchBar(searchBar: UISearchBar, textDidChange searchText: String) {

        let searchText = searchText.trimming(.Whitespace)
        updateSearchResultsWithText(searchText)
    }

    func searchBarSearchButtonClicked(searchBar: UISearchBar) {

        hideKeyboard()
    }

    private func clearSearchResults() {

        filteredFriends = nil
        searchedUsers = []

        updateContactsTableView(scrollsToTop: true)
    }

    private func updateSearchResultsWithText(searchText: String) {

        guard !searchText.isEmpty else {
            clearSearchResults()

            return
        }

        self.keyword = searchText

        let predicate = NSPredicate(format: "nickname CONTAINS[c] %@ OR username CONTAINS[c] %@", searchText, searchText)
        let filteredFriends = friends.filter(predicate)
        self.filteredFriends = filteredFriends

        updateContactsTableView(scrollsToTop: !filteredFriends.isEmpty)

        searchUsersByQ(searchText, failureHandler: nil, completion: { [weak self] users in

            //println("searchUsersByQ users: \(users)")

            dispatch_async(dispatch_get_main_queue()) {

                guard let filteredFriends = self?.filteredFriends else {
                    return
                }

                // 剔除 filteredFriends 里已有的

                var searchedUsers = [DiscoveredUser]()

                let filteredFriendUserIDSet = Set<String>(filteredFriends.map({ $0.userID }))

                for user in users {
                    if !filteredFriendUserIDSet.contains(user.id) {
                        searchedUsers.append(user)
                    }
                }

                self?.searchedUsers = searchedUsers
                
                self?.updateContactsTableView()
            }
        })
    }
}

// MARK: - UITableViewDataSource, UITableViewDelegate

extension SearchContactsViewController: UITableViewDataSource, UITableViewDelegate {

    enum Section: Int {
        case Local
        case Online
    }

    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 2
    }

    private func numberOfRowsInSection(section: Int) -> Int {
        guard let section = Section(rawValue: section) else {
            return 0
        }

        func numberOfRowsWithCountOfItems(countOfItems: Int) -> Int {
            let count = countOfItems
            if count > 0 {
                return 1 + count
            } else {
                return 0
            }
        }

        switch section {
        case .Local:
            return numberOfRowsWithCountOfItems(countOfFilteredFriends)
        case .Online:
            return numberOfRowsWithCountOfItems(countOfSearchedUsers)
        }
    }

    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return numberOfRowsInSection(section)
    }

    func tableView(tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {

        guard numberOfRowsInSection(section) > 0 else {
            return nil
        }

        let header = tableView.dequeueReusableHeaderFooterViewWithIdentifier(headerIdentifier) as? TableSectionTitleView
        header?.titleLabel.text = nil

        return header
    }

    func tableView(tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {

        guard numberOfRowsInSection(section) > 0 else {
            return 0
        }

        return 15
    }

    func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {

        guard indexPath.row > 0 else {
            return 40
        }

        return 70
    }

    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {

        guard let section = Section(rawValue: indexPath.section) else {
            fatalError("Invalid section!")
        }

        if indexPath.row == 0 {

            let cell = tableView.dequeueReusableCellWithIdentifier(searchSectionTitleCellID) as! SearchSectionTitleCell

            switch section {
            case .Local:
                cell.sectionTitleLabel.text = NSLocalizedString("Friends", comment: "")
            case .Online:
                cell.sectionTitleLabel.text = NSLocalizedString("Users", comment: "")
            }

            return cell
        }

        switch section {

        case .Local:
            let cell = tableView.dequeueReusableCellWithIdentifier(searchedUserCellID) as! SearchedUserCell
            return cell

        case .Online:
            let cell = tableView.dequeueReusableCellWithIdentifier(searchedDiscoveredUserCellID) as! SearchedDiscoveredUserCell
            return cell
        }
    }

    private func friendAtIndex(index: Int) -> User? {

        let friend = filteredFriends?[safe: index]
        return friend
    }

    func tableView(tableView: UITableView, willDisplayCell cell: UITableViewCell, forRowAtIndexPath indexPath: NSIndexPath) {

        guard indexPath.row > 0 else {
            return
        }



        guard let section = Section(rawValue: indexPath.section) else {
            return
        }

        let itemIndex = indexPath.row - 1

        switch section {

        case .Local:

            guard let friend = friendAtIndex(itemIndex) else {
                return
            }
            guard let cell = cell as? SearchedUserCell else {
                return
            }

            cell.configureWithUserRepresentation(friend, keyword: keyword)

        case .Online:

            let discoveredUser = searchedUsers[itemIndex]

            guard let cell = cell as? SearchedDiscoveredUserCell else {
                return
            }

            cell.configureWithUserRepresentation(discoveredUser, keyword: keyword)
        }
    }

    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {

        defer {
            tableView.deselectRowAtIndexPath(indexPath, animated: true)
        }

        guard indexPath.row > 0 else {
            return
        }

        hideKeyboard()

        guard let section = Section(rawValue: indexPath.section) else {
            return
        }

        let itemIndex = indexPath.row - 1

        switch section {

        case .Local:

            if let friend = friendAtIndex(itemIndex) {
                performSegueWithIdentifier("showProfile", sender: friend)
            }

        case .Online:

            let discoveredUser = searchedUsers[itemIndex]
            performSegueWithIdentifier("showProfile", sender: Box<DiscoveredUser>(discoveredUser))
        }
    }
}

