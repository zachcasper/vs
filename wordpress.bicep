extension radius
extension radiusResources

param environment string

resource wordpress 'Applications.Core/applications@2023-10-01-preview' = {
  name: 'wordpress'
  properties: {
    environment: environment
  }
}

resource frontend 'Radius.Resources/webService@2023-10-01-preview' = {
  name: 'frontend'
  properties: {
    application: wordpress.id
    environment: environment
    ingress: true
    cache: false
    container: {
      image: 'wordpress:6.2.1-apache'
      ports: {
        http: {
          containerPort: 80
          protocol: 'TCP'
        }
      }
      env: {
        WORDPRESS_DB_HOST: {
          value: mysql.properties.status.binding.host
        }
        WORDPRESS_DB_USER: {
          value: mysql.properties.status.binding.username
        }
        WORDPRESS_DB_PASSWORD: {
          value: mysql.properties.status.binding.password
        }
      }
      resources: {
        requests: {
          cpu: 1
          memory: '256Mi'
        }
        limits: {
          cpu: 1
          memory: '1Gi'
        }
      }
    }
  }
}

resource mysql 'Radius.Resources/mySQL@2023-10-01-preview' = {
  name: 'mysql'
  properties: {
    application: wordpress.id
    environment: environment
    size: 'M'
  }
}
