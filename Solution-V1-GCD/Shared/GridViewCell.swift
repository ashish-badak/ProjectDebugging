import UIKit
import PhotosUI

class GridViewCell: UICollectionViewCell {
    static let livePhotoBadge = PHLivePhotoView.livePhotoBadgeImage(options: .overContent)
    private static let cornerRadius: CGFloat = 15

    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var livePhotoBadgeImageView: UIImageView!
    
    var representedAssetIdentifier: String!

    override func awakeFromNib() {
        super.awakeFromNib()
        
        setupView()
        setupShadow()
    }
    
    private func setupView() {
        /// - NOTE: Live badge is a in a way static image so setting it only once
        livePhotoBadgeImageView.image = Self.livePhotoBadge
        livePhotoBadgeImageView.isHidden = true
    }
    
    private func setupShadow() {
        /// - NOTE: There is no need to redraw shadow in `configure(image:)` call
        ///         It gets redrawn everytime cell configuration is invoked
        ///         So moved it here.
        ///         Also, adjusted some shadow params to drop visually appealing shadow.
        imageView.layer.cornerRadius = Self.cornerRadius
        imageView.clipsToBounds = true

        contentView.layer.shadowColor = UIColor.gray.cgColor
        contentView.layer.shadowRadius = 2
        contentView.layer.shadowOffset = .zero
        contentView.layer.shadowOpacity = 0.8
        
        /// - NOTE: Core Animation computes shadow path internally if not provided.
        ///         By providing shadow path we help to avoid that computation and make it faster.
        ///         In example project, cell size is fixed so confiruing `shadowPath` here inside `awakeFromNib()`
        ///         Else we should do it inside `layoutSubviews()`
        /// Reference: - https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/ImprovingAnimationPerformance/ImprovingAnimationPerformance.html
        ///
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: Self.cornerRadius
        ).cgPath
        
        /// - NOTE: Rasterization helps to cache bitmap and avoids recomputation
        contentView.layer.shouldRasterize = true
        contentView.layer.rasterizationScale = UIScreen.main.scale
    }
    
    func configure(image: UIImage?, isLiveImage: Bool) {
        imageView.image = image
        
        /// - NOTE: Live image badge is hidden and shown as needed
        livePhotoBadgeImageView.isHidden = isLiveImage == false
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        livePhotoBadgeImageView.isHidden = true
    }
}
