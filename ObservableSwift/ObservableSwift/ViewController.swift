//
//  ViewController.swift
//  ObservableSwift
//
//  Created by Tung Nguyen on 11/8/18.
//  Copyright © 2018 Tung Nguyen. All rights reserved.
//

import UIKit

class MyObject: ObservableObject {
    static let shared = MyObject()
    
    @objc dynamic var title: String = ""
}

class MyView: UIView {
    var obj: MyObject?
    
    var btn: UIButton!
    
    func layout() {
        MyObject.shared.title = "MyView"
        
        backgroundColor = UIColor.lightGray
        
        btn = UIButton(type: UIButton.ButtonType.custom)
        btn.frame = CGRect(x: 20, y: 20, width: 40, height: 30)
        btn.addTarget(self, action: #selector(btnPressed), for: UIControl.Event.touchUpInside)
        btn.setTitle("Change", for: UIControl.State.normal)
        addSubview(btn)
    }
    
    @objc func btnPressed() {
        btn.isSelected = !btn.isSelected
        if btn.isSelected {
            MyObject.shared.title = "Selected"
        }
        else {
            MyObject.shared.title = "MyView"
        }
    }
}

class ViewController: UIViewController {
    
    @IBOutlet weak var titleLabel: UILabel!
    
    let bag = CleanBag()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        MyObject.shared.subcribeKeySelector(#keyPath(MyObject.title), binding: { [weak self] (key, newTitle) in
            guard let `self` = self else {return}
            print("did changed: \(String(describing: newTitle))")
            self.titleLabel.text = (newTitle as? String) ?? ""
        }).cleanupBy(bag)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        MyObject.shared.title = "ViewController"
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 2) { [weak self] in
            guard let `self` = self else {return}
            let v = MyView(frame: CGRect(x: 20, y: 100, width: 200, height: 200))
            v.layout()
            self.view.addSubview(v)
        }
    }
}

