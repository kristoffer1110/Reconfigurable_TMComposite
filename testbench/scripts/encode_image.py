import sys
sys.path.append('../lib')

import numpy as np
from PIL import Image
from encoding import thermometer_encode_array

# Load the image
img = Image.open('../data/test_image_32x32_rgb.png')
arr = np.array(img)

# Apply thermometer encoding to each pixel value (each channel)
arr_encoded = thermometer_encode_array(arr)

# Create new image from encoded array
img_encoded = Image.fromarray(arr_encoded)

# Save the encoded image
img_encoded.save('../data/encoded_test_image_32x32_rgb.png')

print("Encoded image saved as encoded_test_image_32x32_rgb.png")