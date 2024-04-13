import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from sklearn.linear_model import LinearRegression
from sklearn.model_selection import train_test_split
from mpl_toolkits.mplot3d import Axes3D

# Load the data
data = pd.read_csv('bt.csv')  # Update with your file path

# Select features and target
X = data[['m_cost', 'e_cost']]
y = data['bp300bt']

# Split the data into training and testing sets
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# Initialize and train the linear regression model
model = LinearRegression()
model.fit(X_train, y_train)

# Generate mesh grid for the input space for plotting
x_mesh, y_mesh = np.meshgrid(
    np.linspace(X['m_cost'].min(), X['m_cost'].max(), 100),
    np.linspace(X['e_cost'].min(), X['e_cost'].max(), 100)
)

# Flatten the grid to create input for predictions
z_mesh = model.predict(np.c_[x_mesh.ravel(), y_mesh.ravel()])
z_mesh = z_mesh.reshape(x_mesh.shape)

# Creating the plot
fig = plt.figure(figsize=(10, 8))
ax = fig.add_subplot(111, projection='3d')

# Scatter plot for actual data points
ax.scatter(X['m_cost'], X['e_cost'], y, color='blue', label='Actual Data')

# Surface plot for the regression prediction
ax.plot_surface(x_mesh, y_mesh, z_mesh, color='orange', alpha=0.5, edgecolor='none')

# Setting labels and title
ax.set_xlabel('Material Cost (m_cost)')
ax.set_ylabel('Energy Cost (e_cost)')
ax.set_zlabel('bp300bt')
ax.set_title('3D Plot of Actual Data and Predicted Regression Plane')

# Show the plot
plt.show()
