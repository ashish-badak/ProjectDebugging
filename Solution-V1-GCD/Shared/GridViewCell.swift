import UIKit
import PhotosUI

class GridViewCell: UICollectionViewCell {
    static let livePhotoBadge = PHLivePhotoView.livePhotoBadgeImage(options: .overContent)

    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var livePhotoBadgeImageView: UIImageView!
    
    var representedAssetIdentifier: String!

    override func awakeFromNib() {
        super.awakeFromNib()
        
        
        /// - NOTE: There is no need to redraw shadow in `configure(image:)` call
        ///         It gets redrawn everytime cell configuration is invoked
        ///         So moved it here.
        ///         Also, adjusted some shadow params to drop visually appealing shadow.
        imageView.layer.cornerRadius = 15.0
        imageView.clipsToBounds = true

        contentView.layer.shadowColor = UIColor.gray.cgColor
        contentView.layer.shadowRadius = 2
        contentView.layer.shadowOffset = .zero
        contentView.layer.shadowOpacity = 0.8
        contentView.layer.shouldRasterize = true
        contentView.layer.rasterizationScale = UIScreen.main.scale
        
        /// - NOTE: Live badge is a in a way stativ image so setting it only once
        livePhotoBadgeImageView.image = Self.livePhotoBadge
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
