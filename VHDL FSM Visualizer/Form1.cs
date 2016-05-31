using System;
using System.Collections.Generic;
using System.IO;
using System.Windows.Forms;
using GraphX.PCL.Common.Enums;
using GraphX.PCL.Logic.Algorithms.OverlapRemoval;
using GraphX.PCL.Logic.Models;
using GraphX.Controls;
using GraphX.Controls.Models;
using QuickGraph;
using System.Windows;
using System.Linq;
using System.Drawing;
using VHDL_FSM_Visualiser.Models;

namespace VHDL_FSM_Visualizer
{
    public partial class Form1 : Form
    {
        //FSM Vars
        List<FSM_State> fsmStates = new List<FSM_State>();
        GraphLayoutOptions graphLayoutOptions = new GraphLayoutOptions();
        string vhdlFilePath;
        string[] vhdlFileLinesOfCode;

        //GraphX Vars
        private ZoomControl _zoomctrl;
        private FSMGraphArea _gArea;

        public Form1()
        {
            InitializeComponent();
            this.Shown += new System.EventHandler(this.Form1_Shown);
        }

        private void Form1_Load(object sender, EventArgs e)
        {
            toolStripComboBox1.SelectedIndex = (int) graphLayoutOptions.layoutAlgorithm;
            toolStripComboBox2.SelectedIndex = (int) graphLayoutOptions.edgeRoutingAlgorithm;
            wpfHost.Child = GenerateWpfVisuals();
            _zoomctrl.ZoomToFill();

        }

        private void Form1_Shown(object sender, EventArgs e)
        {
            Utils.WriteLogFile(Utils.logType.Info, "Welcome to VHDL FSM Visualizer");
        }

        private UIElement GenerateWpfVisuals()
        {

            _zoomctrl = new ZoomControl();
            ZoomControl.SetViewFinderVisibility(_zoomctrl, Visibility.Visible);
            /* ENABLES WINFORMS HOSTING MODE --- >*/
            var logic = new GXLogicCore<DataVertex, DataEdge, BidirectionalGraph<DataVertex, DataEdge>>();
            _gArea = new FSMGraphArea
            {
                EnableWinFormsHostingMode = true,
                LogicCore = logic,
                EdgeLabelFactory = new DefaultEdgelabelFactory()
            };
            _gArea.ShowAllEdgesLabels(graphLayoutOptions.showAllEdgesLabels);
            logic.Graph = GenerateGraph();
            logic.DefaultLayoutAlgorithm = graphLayoutOptions.layoutAlgorithm;
            logic.DefaultLayoutAlgorithmParams = logic.AlgorithmFactory.CreateLayoutParameters(graphLayoutOptions.layoutAlgorithm);
            logic.EdgeCurvingEnabled = true;
            logic.EnableParallelEdges = true;
            //((LinLogLayoutParameters)logic.DefaultLayoutAlgorithmParams). = 100;
            logic.DefaultOverlapRemovalAlgorithm = graphLayoutOptions.overlapRemovalAlgorithm;
            logic.DefaultOverlapRemovalAlgorithmParams = logic.AlgorithmFactory.CreateOverlapRemovalParameters(graphLayoutOptions.overlapRemovalAlgorithm);
            ((OverlapRemovalParameters)logic.DefaultOverlapRemovalAlgorithmParams).HorizontalGap = graphLayoutOptions.overlapRemovalHorizontalGap;
            ((OverlapRemovalParameters)logic.DefaultOverlapRemovalAlgorithmParams).VerticalGap = graphLayoutOptions.overlapRemovalVerticalGap;
            logic.DefaultEdgeRoutingAlgorithm = graphLayoutOptions.edgeRoutingAlgorithm;
            logic.AsyncAlgorithmCompute = false;
            _zoomctrl.Content = _gArea;
            _gArea.RelayoutFinished += gArea_RelayoutFinished;


            var myResourceDictionary = new ResourceDictionary { Source = new Uri("Templates\\template.xaml", UriKind.Relative) };
            _zoomctrl.Resources.MergedDictionaries.Add(myResourceDictionary);

            return _zoomctrl;
        }

        void gArea_RelayoutFinished(object sender, EventArgs e)
        {
            _zoomctrl.ZoomToFill();
        }

        private FSMGraph GenerateGraph()
        {
            //FOR DETAILED EXPLANATION please see SimpleGraph example project
            var dataGraph = new FSMGraph();
            foreach (FSM_State state in fsmStates)
            {
                var dataVertex = new DataVertex(state.name, state.whenStmentTxt);
                dataGraph.AddVertex(dataVertex);
            }
            var vlist = dataGraph.Vertices.ToList();
            for (int i = 0; i < vlist.Count; i++)
            {
                FSM_State stateDst = fsmStates[i];
                for (int j = 0; j < vlist.Count; j++)
                {
                    FSM_State stateSrc = fsmStates[j];
                    if (stateSrc.next_states.ContainsKey(stateDst))
                    {
                        var dataEdge = new DataEdge(vlist[j], vlist[i]) { Condition = stateSrc.next_states[stateDst] };
                        dataGraph.AddEdge(dataEdge);
                    }
                }
            }
            return dataGraph;
        }

        private void loadFileBtn_Click(object sender, EventArgs e)
        {
            DialogResult result = openFileDialog1.ShowDialog(); // Show the dialog.
            if (result == DialogResult.OK) // Test result.
            {
                Utils.WriteLogFile(Utils.logType.Info, "Loading File: ", openFileDialog1.FileName);
                LoadVHDLFile(openFileDialog1.FileName, true);
                fileSystemWatcher1.Filter = openFileDialog1.SafeFileName;
                fileSystemWatcher1.Path = Path.GetDirectoryName(openFileDialog1.FileName);
                Utils.WriteLogFile(Utils.logType.Info, "Filewatcher attached to file: ", fileSystemWatcher1.Filter);
            }
        }

        private void refreshGraph(bool relayout)
        {
            _gArea.GenerateGraph(true);
            _gArea.SetVerticesDrag(true, true);
            if (relayout)
            {
                _zoomctrl.ZoomToFill();
            }
        }

        private void refreshGraphBtn_Click(object sender, EventArgs e)
        {
            refreshGraph(true);
        }


        private void fileSystemWatcher1_Changed(object sender, FileSystemEventArgs e)
        {
            Utils.WriteLogFile(Utils.logType.Info, "File changed: ", vhdlFilePath);
            LoadVHDLFile(vhdlFilePath, true);
        }

        private bool LoadVHDLFile(string filePath, bool relayout)
        {
            if (filePath != vhdlFilePath)
            {
                vhdlFilePath = filePath;
            }
            toolStripProgressBar1.Visible = true;
            toolStripProgressBar1.Value = 0; //zero progress bar
            Cursor.Current = Cursors.WaitCursor; //make wait cursor
            try
            {
                toolStripProgressBar1.Value = 10;
                bool fileRead = false;
                while (!fileRead)
                {
                    try
                    {
                        vhdlFileLinesOfCode = File.ReadAllLines(vhdlFilePath);
                        fileRead = true;
                    }
                    catch (Exception)
                    {
                        fileRead = false;
                    }
                }
                if (fileRead)
                {
                    toolStripProgressBar1.Value = 30;
                    Utils.WriteLogFile(Utils.logType.Info, "Parsing states enumeration: ");
                    fsmStates = Utils.vhdlParseStatesDecleration(vhdlFileLinesOfCode, fsmTypeTxtBox.Text);
                    Utils.WriteLogFile(Utils.logType.Info, "States found, N = ", fsmStates.Count.ToString());
                    if (fsmStates.Count > 0)
                    {
                        Utils.WriteLogFile(Utils.logType.Info, "Parsing states transitions: ");
                        fsmStates = Utils.vhdlParseStatesTransitions(fsmStates, vhdlFileLinesOfCode, currStateTxtBox.Text, nextStateTxtBox.Text);
                        toolStripProgressBar1.Value = 70;
                        wpfHost.Child = GenerateWpfVisuals();
                        refreshGraph(relayout);
                        Cursor.Current = Cursors.Default; // make default cursor
                        toolStripProgressBar1.Value = 100; //full progress bar
                        toolStripProgressBar1.Visible = false;
                        return true;
                    }
                    else
                    {
                        Utils.WriteLogFile(Utils.logType.Error, "No states where found", fsmStates.Count.ToString());
                        toolStripProgressBar1.Value = 0;
                        return false;
                    }
                }
                else
                {
                    Utils.WriteLogFile(Utils.logType.Error, "Could not read file", filePath);
                    return false;
                }
            }
            catch (IOException ex)
            {
                Utils.WriteLogFile(Utils.logType.Error, "Exception occured with message: " + ex.Message, "Data: \n" + ex.Data);
                return false;
            }
        }

        private void splitContainer1_Panel2_Paint(object sender, PaintEventArgs e)
        {

        }

        private void splitContainer1_Paint(object sender, PaintEventArgs e)
        {
            var control = sender as SplitContainer;
            //paint the three dots'
            System.Drawing.Point[] points = new System.Drawing.Point[5];
            var w = control.Width;
            var h = control.Height;
            var d = control.SplitterDistance;
            var sW = control.SplitterWidth;

            //calculate the position of the points'
            if (control.Orientation == Orientation.Horizontal)
            {
                points[0] = new System.Drawing.Point((w / 2), d + (sW / 2));
                points[1] = new System.Drawing.Point(points[0].X - 10, points[0].Y);
                points[2] = new System.Drawing.Point(points[0].X + 10, points[0].Y);
                points[3] = new System.Drawing.Point(points[0].X - 20, points[0].Y);
                points[4] = new System.Drawing.Point(points[0].X + 20, points[0].Y);
            }
            else
            {
                points[0] = new System.Drawing.Point(d + (sW / 2), (h / 2));
                points[1] = new System.Drawing.Point(points[0].X, points[0].Y - 10);
                points[2] = new System.Drawing.Point(points[0].X, points[0].Y + 10);
                points[1] = new System.Drawing.Point(points[0].X, points[0].Y - 20);
                points[2] = new System.Drawing.Point(points[0].X, points[0].Y + 20);
            }

            foreach (System.Drawing.Point p in points)
            {
                p.Offset(-2, -2);
                e.Graphics.FillEllipse(SystemBrushes.ControlDark,
                    new Rectangle(p, new System.Drawing.Size(3, 3)));

                p.Offset(1, 1);
                e.Graphics.FillEllipse(SystemBrushes.ControlLight,
                    new Rectangle(p, new System.Drawing.Size(3, 3)));
            }
        }

        private void toolStripComboBox1_SelectedIndexChanged(object sender, EventArgs e)
        {
            if (_gArea != null)
            {
                graphLayoutOptions.layoutAlgorithm = (LayoutAlgorithmTypeEnum)toolStripComboBox1.SelectedIndex;
                _gArea.LogicCore.DefaultLayoutAlgorithm = graphLayoutOptions.layoutAlgorithm;
                refreshGraph(true);
            }
        }

        private void toolStripComboBox2_SelectedIndexChanged(object sender, EventArgs e)
        {
            if (_gArea != null)
            {
                graphLayoutOptions.edgeRoutingAlgorithm = (EdgeRoutingAlgorithmTypeEnum)toolStripComboBox2.SelectedIndex;
                _gArea.LogicCore.DefaultLayoutAlgorithm = graphLayoutOptions.layoutAlgorithm;
                refreshGraph(true);
            }
        }

        private void toolStripButton1_CheckedChanged(object sender, EventArgs e)
        {
            if (_gArea != null)
            {
                _gArea.ShowAllEdgesLabels(toolStripButton1.Checked);
                refreshGraph(true);
            }
        }
    }
}
