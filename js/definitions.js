var config = {

  tagline: "The Laboratory</br>Operating System",
  documentation_url: "http://localhost:4000/aquarium",
  title: "Flow Cytometry",
  navigation: [

    {
      category: "Overview",
      contents: [
        { name: "Introduction", type: "local-md", path: "README.md" },
        { name: "About this Workflow", type: "local-md", path: "ABOUT.md" },
        { name: "License", type: "local-md", path: "LICENSE.md" },
        { name: "Issues", type: "external-link", path: 'https://github.com/klavinslab/flow-cytometry/issues' }
      ]
    },

    

      {

        category: "Operation Types",

        contents: [

          
            {
              name: 'Cytometer Bead Calibration',
              path: 'operation_types/Cytometer_Bead_Calibration' + '.md',
              type: "local-md"
            },
          
            {
              name: 'Flow Cytometry 96 well',
              path: 'operation_types/Flow_Cytometry_96_well' + '.md',
              type: "local-md"
            },
          

        ]

      },

    

    

      {

        category: "Libraries",

        contents: [

          
            {
              name: 'BDAriaIII',
              path: 'libraries/BDAriaIII' + '.html',
              type: "local-webpage"
            },
          
            {
              name: 'Cytometers',
              path: 'libraries/Cytometers' + '.html',
              type: "local-webpage"
            },
          
            {
              name: 'SonySH800S',
              path: 'libraries/SonySH800S' + '.html',
              type: "local-webpage"
            },
          

        ]

    },

    

    
      { category: "Sample Types",
        contents: [
          
        ]
      },
      { category: "Containers",
        contents: [
          
        ]
      }
    

  ]

};
