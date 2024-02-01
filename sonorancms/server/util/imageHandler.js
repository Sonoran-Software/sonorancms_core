const filesystem = require('fs').promises;
const sizeOf = require('image-size');

exports("SaveBase64ToFile", function (base64String, filepath, filename) {
    return new Promise((resolve, reject) => {
        // Get the base64 image data
        let base64Image = base64String.split(';base64,').pop();

        // Get the dimensions of the image
        let dimensions = sizeOf(Buffer.from(base64Image, 'base64'));

        // Check if the image is 100x100
        if (dimensions.width === 100 && dimensions.height === 100) {
            // Save the image
            filesystem.writeFile(filepath, base64Image, { encoding: 'base64' })
                .then(() => {
                    console.log('File saved successfully');
                    resolve({ success: true, error: filename });
                })
                .catch(err => {
                    console.log(err);
                    reject({ success: false, error: err });
                });
        } else {
            // Return an error
            console.log('Image must be 100x100');
            reject({ success: false, error: 'Image must be 100x100' });
        }
    });
});
